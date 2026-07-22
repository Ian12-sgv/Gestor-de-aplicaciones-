-- AlterTable
ALTER TABLE "AppVersion" ADD COLUMN     "archiveEntryCount" INTEGER,
ADD COLUMN     "contentType" VARCHAR(120),
ADD COLUMN     "fileExtension" VARCHAR(20),
ADD COLUMN     "originalFileName" VARCHAR(255);
