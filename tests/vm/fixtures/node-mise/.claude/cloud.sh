# The fixture of tests/vm for the custom stack with mise: Node 20 from .tool-versions, no database.
SITE_URL="http://localhost:3000"
SITE_CHECK_PATH="/"
background_workers() {
    echo "web|node server.js|3000"
}
