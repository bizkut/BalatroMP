# Stage 1: Build the love.js package using love.js CLI from Davidobot/love.js GitHub repo
FROM node:18-alpine AS builder

# Install git and zip
RUN apk add --no-cache git zip

# Clone Davidobot/love.js repository
WORKDIR /opt
RUN git clone --depth 1 https://github.com/Davidobot/love.js.git love.js-davidobot

# Install dependencies for the cloned love.js CLI tool
WORKDIR /opt/love.js-davidobot
# Check if package.json exists before running npm install
# Some versions/forks might not have it or might bundle dependencies.
# Davidobot/love.js does have a package.json with commander.
RUN if [ -f package.json ]; then npm install; fi

WORKDIR /usr/src/app

# Copy essential files for the build process first
COPY package.json ./
COPY package-lock.json* ./
COPY main.lua ./
COPY conf.lua ./
COPY web_api.lua ./
COPY engine ./engine
COPY functions ./functions
COPY resources ./resources
COPY localization ./localization
COPY *.lua ./

# The package.json's build:lovejs script is:
# "build:lovejs": "mkdir -p /tmp/gamedata && cp -R *.lua engine/ functions/ resources/ localization/ conf.lua main.lua web_api.lua /tmp/gamedata/ 2>/dev/null || : && cd /tmp/gamedata && zip -r /tmp/game.love . && cd /usr/src/app && love.js /tmp/game.love ./game_web -c --title Balatro && rm -rf /tmp/gamedata /tmp/game.love"
# We need to replace the `love.js` command in that script or call our cloned version directly.
# For clarity, let's do the packaging steps directly here instead of relying on package.json for this part.

# 1. Create a temporary directory for game files
RUN mkdir -p /tmp/gamedata
# 2. Copy necessary game files to /tmp/gamedata
# Using existing files in /usr/src/app after the COPY operations above
RUN cp -R *.lua engine/ functions/ resources/ localization/ conf.lua main.lua web_api.lua /tmp/gamedata/ 2>/dev/null || :
# 3. Create game.love
RUN cd /tmp/gamedata && zip -r /tmp/game.love .
# 4. Run the cloned love.js CLI on the game.love
# The output path ./game_web will be relative to /usr/src/app
# Allocate 128MB of memory for the Emscripten module (128 * 1024 * 1024 = 134217728 bytes)
RUN node /opt/love.js-davidobot/index.js /tmp/game.love ./game_web -c --title Balatro -m 134217728
# 5. Clean up (optional in builder, but good practice)
RUN rm -rf /tmp/gamedata /tmp/game.love


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
COPY ./index.html ./index.html

# Copy the packaged game from the builder stage
COPY --from=builder /usr/src/app/game_web ./game_web

# Create and set permissions for the saves directory
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves \
    && chown -R node:node /usr/src/app/game_web \
    && chown node:node /usr/src/app/index.html

# Expose Port
EXPOSE 3000

# Start Command
CMD [ "npm", "start" ]
