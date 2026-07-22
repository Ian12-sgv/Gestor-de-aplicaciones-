import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import "dotenv/config";

const SQLSERVER_SCHEME = "sqlserver://";

async function main() {
  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required.");
  }

  if (!databaseUrl.startsWith(SQLSERVER_SCHEME)) {
    throw new Error("DATABASE_URL must use sqlserver://.");
  }

  const { databaseName, masterUrl } = resolveMasterUrl(databaseUrl);
  const tempDir = await mkdtemp(path.join(tmpdir(), "pdb-store-sqlserver-"));
  const sqlFilePath = path.join(tempDir, "create-db.sql");

  try {
    await writeFile(sqlFilePath, buildCreateDatabaseSql(databaseName), "utf8");
    await runPrismaDbExecute(masterUrl, sqlFilePath);
    console.log(`SQL Server database ready: ${databaseName}`);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function resolveMasterUrl(databaseUrl: string) {
  const parts = databaseUrl.substring(SQLSERVER_SCHEME.length).split(";");
  const endpoint = parts.shift();
  const settings = parts.map((part) => part.split("="));
  const databaseSetting = settings.find(
    ([key]) => key?.trim().toLowerCase() === "database",
  );
  const databaseName = databaseSetting?.[1]?.trim();

  if (!endpoint) {
    throw new Error("DATABASE_URL must include a SQL Server host.");
  }

  if (!databaseName) {
    throw new Error("DATABASE_URL must include database=<name>.");
  }

  const rewrittenSettings = settings.map(([key, ...valueParts]) => {
    const value = valueParts.join("=");

    if (key.trim().toLowerCase() === "database") {
      return "database=master";
    }

    return `${key}=${value}`;
  });

  return {
    databaseName,
    masterUrl: `${SQLSERVER_SCHEME}${endpoint};${rewrittenSettings.join(";")}`,
  };
}

function buildCreateDatabaseSql(databaseName: string) {
  const escapedString = databaseName.replaceAll("'", "''");
  const escapedIdentifier = databaseName.replaceAll("]", "]]");

  return `
IF DB_ID(N'${escapedString}') IS NULL
BEGIN
  CREATE DATABASE [${escapedIdentifier}];
END;
`;
}

function runPrismaDbExecute(masterUrl: string, sqlFilePath: string) {
  return new Promise<void>((resolve, reject) => {
    const command = process.platform === "win32" ? "npx.cmd" : "npx";
    const child = spawn(
      command,
      ["prisma", "db", "execute", "--url", masterUrl, "--file", sqlFilePath],
      {
        shell: false,
        stdio: "inherit",
      },
    );

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(new Error(`prisma db execute failed with exit code ${code}`));
    });
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
