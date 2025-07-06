# Stage 1: Build the love.js package using npm version of love.js CLI
FROM node:18-alpine AS builder

# Install zip for creating .love file (optional, but good practice if we decide to make a .love first)
# and install love.js globally
RUN apk add --no-cache zip && npm install love.js --global

WORKDIR /usr/src/app

# Copy all application code
# Note: If the project is large, selectively copying (package.json first, then sources) is better for caching.
# For simplicity here, copying all. This assumes package.json is at the root of the context.
COPY . .

# Option 1: Package the current directory directly (if main.lua and conf.lua are at root)
# RUN love.js . ./game_web -c --title Balatro
# This command is now typically run via npm scripts as defined in package.json

# Option 2: Or, if package.json has the build script (more common)
# First, ensure all dependencies (including dev like love.js if not global) are installed
# RUN npm install # This would install love.js if it's in devDependencies
RUN npm run build:lovejs # This script in package.json should be: "love.js . game_web -c --title Balatro"

# Stage 2: Setup the Node.js server and serve the packaged game
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package.json and install runtime dependencies
COPY package.json ./
COPY package-lock.json* ./
RUN npm install --omit=dev --ignore-scripts

# Copy the server application files
COPY server.js ./
COPY web_api.lua ./
COPY index.html ./ # This is the root index.html for the Davidobot/love.js style player

# Copy the packaged game from the builder stage
COPY --from=builder /usr/src/app/game_web ./game_web

# Create and set permissions for the saves directory
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves \
    && chown -R node:node /usr/src/app/game_web # Ensure node user owns game_web too

# Expose Port
EXPOSE 3000

# Start Command
CMD [ "npm", "start" ]
