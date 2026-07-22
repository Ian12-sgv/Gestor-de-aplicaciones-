ALTER TABLE "User"
ADD COLUMN "passwordMustChange" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "passwordChangedAt" TIMESTAMP(3);

