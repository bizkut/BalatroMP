# 1. Base Image
FROM node:18-alpine AS builder

# 2. Working Directory
WORKDIR /usr/src/app

# 3. Copy package.json and install dependencies
COPY package.json ./
# If package-lock.json exists, copy it too for deterministic installs
COPY package-lock.json* ./
RUN npm install --omit=dev
# Install love.js globally or as a dev dependency if needed for build script.
# For the build script "npm run build:lovejs", love.js needs to be available.
# If it's in devDependencies, npm install (without --omit=dev) would get it.
# Or install it globally for the build stage:
RUN npm install love.js --global

# 4. Copy Application Code
COPY . .

# 5. Build Love.js Game
# Ensure the output directory 'game_web' is writable by the node user
# The 'node' user in the official node images might not have write permission in /usr/src/app directly for new dirs
# RUN mkdir -p game_web && chown node:node game_web
# The build command is in package.json's scripts: "build:lovejs": "npx love.js . game_web -c --title Balatro"
# npx will use the locally installed love.js from node_modules/.bin if available, or the global one.
RUN npm run build:lovejs

# New stage for a smaller final image
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy only necessary files from the builder stage
COPY package.json ./
COPY package-lock.json* ./
RUN npm install --omit=dev --ignore-scripts
# We only need runtime dependencies (express) here, not love.js CLI tool

COPY --from=builder /usr/src/app/server.js ./server.js
COPY --from=builder /usr/src/app/index.html ./index.html
COPY --from=builder /usr/src/app/web_api.lua ./web_api.lua
# Copy the packaged game output
COPY --from=builder /usr/src/app/game_web ./game_web
# Copy the saves directory structure (even if empty, to ensure it exists with correct permissions)
COPY --from=builder /usr/src/app/saves ./saves

# Ensure the 'node' user owns the files and can write to 'saves'
# The node user (UID 1000) is the default user in node:alpine images.
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves

# 6. Expose Port
EXPOSE 3000

# 7. Start Command
CMD [ "npm", "start" ]
