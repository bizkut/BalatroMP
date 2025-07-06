# Stage 1: Build the love.js package using npm version of love.js CLI
FROM node:18-alpine AS builder

RUN apk add --no-cache zip && npm install love.js --global

WORKDIR /usr/src/app

# Copy essential files for the build process first
COPY package.json ./
COPY package-lock.json* ./
# If your main.lua, conf.lua are not at root, adjust paths or copy them specifically
COPY main.lua ./
COPY conf.lua ./
COPY web_api.lua ./
# Copy directories needed for the game
COPY engine ./engine
COPY functions ./functions
COPY resources ./resources
COPY localization ./localization
# Add any other root .lua files or essential assets needed for the .love file or love.js packaging
COPY *.lua ./ 2>/dev/null || :

# Install npm dependencies (if love.js CLI is part of devDependencies and not installed globally)
# RUN npm install

# Run the build script defined in package.json
# This script should handle creating game.love and then running love.js CLI
RUN npm run build:lovejs

# Stage 2: Setup the Node.js server and serve the packaged game
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package.json and install runtime dependencies
COPY package.json ./
COPY package-lock.json* ./
RUN npm install --omit=dev --ignore-scripts

# Copy the server application files
COPY server.js ./server.js
COPY web_api.lua ./web_api.lua
# Explicitly copy index.html from the build context's root to the current directory in the image
COPY ./index.html ./index.html

# Copy the packaged game from the builder stage
COPY --from=builder /usr/src/app/game_web ./game_web

# Create and set permissions for the saves directory
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves \
    && chown -R node:node /usr/src/app/game_web \
    && chown node:node /usr/src/app/index.html # Also chown the copied index.html

# Expose Port
EXPOSE 3000

# Start Command
CMD [ "npm", "start" ]
