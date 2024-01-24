#!/usr/bin/env node
'use strict';
/**
 * @author github.com/tintinweb
 * @license MIT
 *
 * Based on:
 *  - https://github.com/Consensys/solidity-metrics/blob/master/src/cli.js
 *  - https://github.com/Consensys/vscode-solidity-metrics/blob/master/src/extension.js
 *
 */

const glob = require("glob");
const fs = require("fs");
const { SolidityMetricsContainer } = require("solidity-code-metrics");
const { exportAsHtml } = require("solidity-code-metrics/src/metrics/helper");

const globExclusions = [
  "**/node_modules",
  "**/mock*",
  "**/test*",
  "**/migrations",
  "**/Migrations.sol",
  "lib",
  "**/external",
  "**/libraries",
  "**/interfaces",
];

function getWsGitInfo(rootPath) {
  let branch = "unknown_branch";
  let commit = "unknown_commit";
  let remote = "";

  let basePath = rootPath;

  if (fs.existsSync(basePath + "/.git/HEAD")) {
    let branchFile = fs.readFileSync(basePath + "/.git/HEAD").toString('utf-8').trim();
    if (branchFile && branchFile.startsWith("ref: ")) {
      branchFile = branchFile.replace("ref: ", "");

      let branchFileNormalized = path.normalize(basePath + "/.git/" + branchFile);

      if (branchFileNormalized.startsWith(basePath) && fs.existsSync(branchFileNormalized)) {
        branch = branchFile.replace("refs/heads/", "");
        commit = fs.readFileSync(branchFileNormalized).toString('utf-8').trim();
        if (fs.existsSync(basePath + "/.git/FETCH_HEAD")) {
          let fetchHeadData = fs.readFileSync(basePath + "/.git/FETCH_HEAD").toString('utf-8').trim().split("\n");
          if (fetchHeadData.lenght) {
            let fetchHead = fetchHeadData.find(line => line.startsWith(commit)) || fetchHeadData.find(line => line.includes(`branch '${branch}' of `)) || fetchHeadData[0];
            remote = fetchHead.trim().split(/[\s]+/).pop();
          }
        }
      }


    }
  }
  return {
    branch: branch,
    commit: commit,
    remote: remote
  };
}

function convertGlobExclusions(array) {
  let result = "{";
  for (let i = 0; i < array.length; i++) {
    result += array[i];
    if (i < array.length - 1) {
      result += ",";
    }
  }
  result += "}";

  return result;
}

let options = [];

let outputFile = "solidity-metrics.html";

// Get exclusions
process.argv.slice(1,).forEach(f => {
  if (f.startsWith("--exclude")) {
    let globExclusion = f.split("=")[1];
    console.log("excluding", globExclusion);
    globExclusions.push(globExclusion);
  } else if (f.startsWith("--")) {
    options.push(f);
  }
});

// Get inclusions
let includedFiles = [];
process.argv.slice(1,).forEach(f => {
  if (f.endsWith(".sol") && !f.startsWith("--exclude")) {
    console.log("including", f);
    glob.sync(f, { ignore: globExclusions }).forEach(f => includedFiles.push(f));
  }
});

let metrics = new SolidityMetricsContainer("'CLI'", {
  basePath: undefined,
  initDoppelGanger: undefined,
  inputFileGlobExclusions: convertGlobExclusions(globExclusions),
  inputFileGlob: convertGlobExclusions(includedFiles),
  inputFileGlobLimit: undefined,
  debug: true,
  repoInfo: getWsGitInfo("src/"),
});

// Analyse
console.log("analysing");
includedFiles.forEach(f => metrics.analyze(f));

// output
//console.log(metrics.totals());
let dotGraphs = {};
try {
  console.log("generating dot graphs");
  dotGraphs = metrics.getDotGraphs();
} catch (error) {
  console.error(error);
}

console.log("generating markdown report");
metrics.generateReportMarkdown().then(md => {
  console.log("generating HTML report");
  const htmlOutput = exportAsHtml(md, metrics.totals(), dotGraphs);

  console.log("writing report to", outputFile);
  fs.writeFileSync(outputFile, htmlOutput);
});
