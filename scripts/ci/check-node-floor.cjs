#!/usr/bin/env node
"use strict";

const minimum = [22, 23, 4];
const version = (process.argv[2] || process.versions.node)
  .split(".")
  .map((part) => Number.parseInt(part, 10));

if (version.length !== 3 || version.some((part) => !Number.isInteger(part))) {
  console.error(`Could not parse Node.js version: ${process.argv[2] || process.versions.node}`);
  process.exit(2);
}

const belowFloor = version.some((part, index) => {
  if (part !== minimum[index]) return part < minimum[index];
  return false;
});

if (belowFloor) {
  console.error(`Node.js ${version.join(".")} is below the required 22.23.4 floor`);
  process.exit(1);
}

console.log(JSON.stringify({
  commit: process.env.GITHUB_SHA || "local",
  job: process.env.GITHUB_JOB || "local",
  node: version.join("."),
}));
