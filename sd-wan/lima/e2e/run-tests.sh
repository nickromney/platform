#!/bin/sh
# Run Playwright E2E tests

set -e

cd "$(dirname "$0")"

if [ ! -d "node_modules" ]; then
	echo "Installing dependencies..."
	npm install
fi

if [ ! -f "$HOME/Library/Caches/ms-playwright/chromium-*/chrome-linux/chrome" ] &&
	[ ! -f "$HOME/.cache/ms-playwright/chromium-*/chrome-linux/chrome" ]; then
	echo "Installing Playwright browsers..."
	npx playwright install chromium
fi

echo "Running Playwright tests..."
npx playwright test "$@"
