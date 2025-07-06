# Stage 1: Build the .love file and then the love.js package
FROM node:18-alpine AS builder

# Install zip for creating .love file and love.js globally
RUN apk add --no-cache zip && npm install love.js --global

WORKDIR /usr/src/build

# Copy all game source files into a temporary directory for packaging
# This includes Lua files at the root, and all subdirectories like engine/, functions/, resources/, localization/
COPY ./ /tmp/balatro-game-source/

# Create the .love file
# It's crucial that main.lua and conf.lua are at the root of this zip.
# The COPY command above should ensure this if your project structure has them at the root.
RUN cd /tmp/balatro-game-source && \
    zip -r /tmp/game.love .

# Package game.love using love.js CLI
# The output will be in /usr/src/build/game_web
RUN love.js /tmp/game.love ./game_web -c --title Balatro

# Stage 2: Setup the Node.js server and serve the packaged game
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package.json and install runtime dependencies
COPY package.json ./
# If package-lock.json exists, copy it too for deterministic installs
COPY package-lock.json* ./
# Only install production dependencies for the final image
RUN npm install --omit=dev --ignore-scripts

# Copy the server application files
COPY server.js ./
COPY web_api.lua ./
# index.html here is the one I created earlier, which might be slightly different
# from the one love.js generates inside game_web. The one inside game_web/index.html
# is the one that will actually run the game.
COPY index.html ./

# Copy the packaged game from the builder stage
COPY --from=builder /usr/src/build/game_web ./game_web

# Create and set permissions for the saves directory
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves

# Expose Port
EXPOSE 3000

# Start Command
CMD [ "npm", "start" ]
