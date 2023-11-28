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

function convertGlobExclusions() {
  let result = "{";
  for (let i = 0; i < globExclusions.length; i++) {
    result += globExclusions[i];
    if (i < globExclusions.length - 1) {
      result += ",";
    }
  }
  result += "}";

  return result;
}

let options = [];

let outputFile = "solidity-metrics.html";

process.argv.slice(1,).forEach(f => {
  if (f.startsWith("--exclude")) {
    console.log("excluding", f.split("=")[1]);
    globExclusions.push(f.split("=")[1]);
  } else if (f.startsWith("--")) {
    options.push(f);
  }
});

let metrics = new SolidityMetricsContainer("'CLI'", {
  basePath: undefined,
  initDoppelGanger: undefined,
  inputFileGlobExclusions: convertGlobExclusions(),
  inputFileGlob: undefined,
  inputFileGlobLimit: undefined,
  debug: false,
  repoInfo: getWsGitInfo("src/"),
});

process.argv.slice(1,).forEach(f => {
  if (f.endsWith(".sol") && !f.startsWith("--exclude")) {
    console.log("analysing", f);
    // analyze files
    glob.sync(f, {
      ignore: globExclusions,
    }).forEach(fg => metrics.analyze(fg));
  }
});

// output
//console.log(metrics.totals());
let dotGraphs = {};
try {
  dotGraphs = metrics.getDotGraphs();
} catch (error) {
  console.log(error);
}

metrics.generateReportMarkdown().then(md => {
  const htmlOutput = exportAsHtml(md, metrics.totals(), dotGraphs);

  fs.writeFileSync(outputFile, htmlOutput);
});
