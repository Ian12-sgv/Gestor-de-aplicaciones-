import { open, type FileHandle } from "node:fs/promises";
import { inflateRawSync } from "node:zlib";

// Reads package/versionCode/versionName straight from the APK (ZIP + Android binary XML),
// so the server does not need Android build-tools (aapt) installed.

export type BinaryManifestMetadata = {
  packageName: string;
  versionCode: number;
  versionName: string | null;
};

const MANIFEST_ENTRY_NAME = "AndroidManifest.xml";
const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const LOCAL_HEADER_SIGNATURE = 0x04034b50;
const MAX_MANIFEST_BYTES = 16 * 1024 * 1024;

const CHUNK_STRING_POOL = 0x0001;
const CHUNK_XML = 0x0003;
const CHUNK_RESOURCE_MAP = 0x0180;
const CHUNK_START_ELEMENT = 0x0102;
const STRING_POOL_UTF8_FLAG = 0x100;
const TYPE_STRING = 0x03;
const TYPE_INT_DEC = 0x10;
const TYPE_INT_HEX = 0x11;
const NO_INDEX = 0xffffffff;
const ATTR_VERSION_CODE = 0x0101021b;
const ATTR_VERSION_NAME = 0x0101021c;

export async function readBinaryManifestMetadata(filePath: string): Promise<BinaryManifestMetadata> {
  const handle = await open(filePath, "r");

  try {
    const manifest = await readZipEntry(handle, MANIFEST_ENTRY_NAME);
    return parseManifest(manifest);
  } finally {
    await handle.close();
  }
}

async function readBytes(handle: FileHandle, position: number, length: number): Promise<Buffer> {
  const buffer = Buffer.alloc(length);
  const { bytesRead } = await handle.read(buffer, 0, length, position);
  return buffer.subarray(0, bytesRead);
}

async function readZipEntry(handle: FileHandle, entryName: string): Promise<Buffer> {
  const { size } = await handle.stat();
  const tailLength = Math.min(size, 65_557);
  const tail = await readBytes(handle, size - tailLength, tailLength);
  let eocdOffset = -1;

  for (let index = tail.length - 22; index >= 0; index -= 1) {
    if (tail.readUInt32LE(index) === EOCD_SIGNATURE) {
      eocdOffset = index;
      break;
    }
  }

  if (eocdOffset < 0) {
    throw new Error("The file is not a valid ZIP/APK archive.");
  }

  const entryCount = tail.readUInt16LE(eocdOffset + 10);
  const directorySize = tail.readUInt32LE(eocdOffset + 12);
  const directoryOffset = tail.readUInt32LE(eocdOffset + 16);
  const directory = await readBytes(handle, directoryOffset, directorySize);
  let cursor = 0;

  for (let entry = 0; entry < entryCount && cursor + 46 <= directory.length; entry += 1) {
    if (directory.readUInt32LE(cursor) !== CENTRAL_DIRECTORY_SIGNATURE) {
      break;
    }

    const method = directory.readUInt16LE(cursor + 10);
    const compressedSize = directory.readUInt32LE(cursor + 20);
    const uncompressedSize = directory.readUInt32LE(cursor + 24);
    const nameLength = directory.readUInt16LE(cursor + 28);
    const extraLength = directory.readUInt16LE(cursor + 30);
    const commentLength = directory.readUInt16LE(cursor + 32);
    const localHeaderOffset = directory.readUInt32LE(cursor + 42);
    const name = directory.toString("utf8", cursor + 46, cursor + 46 + nameLength);
    cursor += 46 + nameLength + extraLength + commentLength;

    if (name !== entryName) {
      continue;
    }

    if (uncompressedSize > MAX_MANIFEST_BYTES || compressedSize > MAX_MANIFEST_BYTES) {
      throw new Error("AndroidManifest.xml is unexpectedly large.");
    }

    const localHeader = await readBytes(handle, localHeaderOffset, 30);
    if (localHeader.length < 30 || localHeader.readUInt32LE(0) !== LOCAL_HEADER_SIGNATURE) {
      throw new Error("Invalid local header for AndroidManifest.xml.");
    }

    const dataOffset =
      localHeaderOffset + 30 + localHeader.readUInt16LE(26) + localHeader.readUInt16LE(28);
    const data = await readBytes(handle, dataOffset, compressedSize);

    if (method === 0) {
      return data;
    }

    if (method === 8) {
      return inflateRawSync(data);
    }

    throw new Error(`Unsupported ZIP compression method ${method}.`);
  }

  throw new Error("AndroidManifest.xml was not found in the APK.");
}

function parseManifest(xml: Buffer): BinaryManifestMetadata {
  if (xml.length < 8 || xml.readUInt16LE(0) !== CHUNK_XML) {
    throw new Error("AndroidManifest.xml is not in Android binary XML format.");
  }

  let strings: string[] = [];
  let resourceIds: number[] = [];
  let offset = xml.readUInt16LE(2);

  while (offset + 8 <= xml.length) {
    const chunkType = xml.readUInt16LE(offset);
    const chunkSize = xml.readUInt32LE(offset + 4);

    if (chunkSize < 8) {
      break;
    }

    if (chunkType === CHUNK_STRING_POOL) {
      strings = readStringPool(xml, offset);
    } else if (chunkType === CHUNK_RESOURCE_MAP) {
      resourceIds = [];
      for (let index = offset + 8; index + 4 <= offset + chunkSize; index += 4) {
        resourceIds.push(xml.readUInt32LE(index));
      }
    } else if (chunkType === CHUNK_START_ELEMENT) {
      const nameIndex = xml.readUInt32LE(offset + 20);

      if (strings[nameIndex] === "manifest") {
        return readManifestAttributes(xml, offset, strings, resourceIds);
      }
    }

    offset += chunkSize;
  }

  throw new Error("The <manifest> element was not found.");
}

function readManifestAttributes(
  xml: Buffer,
  chunkOffset: number,
  strings: string[],
  resourceIds: number[],
): BinaryManifestMetadata {
  const attributeStart = xml.readUInt16LE(chunkOffset + 24);
  const attributeSize = xml.readUInt16LE(chunkOffset + 26);
  const attributeCount = xml.readUInt16LE(chunkOffset + 28);
  let packageName: string | null = null;
  let versionCode: number | null = null;
  let versionName: string | null = null;

  for (let index = 0; index < attributeCount; index += 1) {
    const base = chunkOffset + 16 + attributeStart + index * attributeSize;
    const nameIndex = xml.readUInt32LE(base + 4);
    const rawValueIndex = xml.readUInt32LE(base + 8);
    const dataType = xml.readUInt8(base + 15);
    const data = xml.readUInt32LE(base + 16);
    const name = strings[nameIndex] ?? "";
    const resourceId = resourceIds[nameIndex];
    const stringValue =
      rawValueIndex !== NO_INDEX
        ? strings[rawValueIndex] ?? null
        : dataType === TYPE_STRING
          ? strings[data] ?? null
          : null;

    if (name === "package") {
      packageName = stringValue;
    } else if (resourceId === ATTR_VERSION_CODE || name === "versionCode") {
      versionCode =
        dataType === TYPE_INT_DEC || dataType === TYPE_INT_HEX
          ? data
          : Number.parseInt(stringValue ?? "", 10);
    } else if (resourceId === ATTR_VERSION_NAME || name === "versionName") {
      versionName = stringValue;
    }
  }

  if (!packageName || versionCode === null || !Number.isInteger(versionCode) || versionCode <= 0) {
    throw new Error("The manifest is missing package or versionCode.");
  }

  return { packageName, versionCode, versionName };
}

function readStringPool(xml: Buffer, chunkOffset: number): string[] {
  const headerSize = xml.readUInt16LE(chunkOffset + 2);
  const stringCount = xml.readUInt32LE(chunkOffset + 8);
  const flags = xml.readUInt32LE(chunkOffset + 16);
  const stringsStart = chunkOffset + xml.readUInt32LE(chunkOffset + 20);
  const isUtf8 = (flags & STRING_POOL_UTF8_FLAG) !== 0;
  const strings: string[] = [];

  for (let index = 0; index < stringCount; index += 1) {
    const stringOffset = stringsStart + xml.readUInt32LE(chunkOffset + headerSize + index * 4);
    strings.push(isUtf8 ? readUtf8String(xml, stringOffset) : readUtf16String(xml, stringOffset));
  }

  return strings;
}

function readUtf8String(xml: Buffer, offset: number): string {
  let cursor = offset;
  // UTF-16 length first (skipped), then the UTF-8 byte length.
  cursor += (xml.readUInt8(cursor) & 0x80) !== 0 ? 2 : 1;
  let byteLength = xml.readUInt8(cursor);
  if ((byteLength & 0x80) !== 0) {
    byteLength = ((byteLength & 0x7f) << 8) | xml.readUInt8(cursor + 1);
    cursor += 2;
  } else {
    cursor += 1;
  }

  return xml.toString("utf8", cursor, cursor + byteLength);
}

function readUtf16String(xml: Buffer, offset: number): string {
  let cursor = offset;
  let length = xml.readUInt16LE(cursor);
  if ((length & 0x8000) !== 0) {
    length = ((length & 0x7fff) << 16) | xml.readUInt16LE(cursor + 2);
    cursor += 4;
  } else {
    cursor += 2;
  }

  return xml.toString("utf16le", cursor, cursor + length * 2);
}
