// The fixture of the custom stack with mise: a site with no dependency, on the Node of .tool-versions.
// Docker's amd64 emulation on an arm Mac rewrites node's arguments in `ps`, so cloud-sync's restart could
// not find `node server.js`. The title puts them back once node has booted; a real VM needs no such line.
process.title = 'node server.js';
require('http').createServer((request, response) => response.end(process.version)).listen(3000, '127.0.0.1');
