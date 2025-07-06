# Stage 1: Build the love.js package using love.js CLI from Davidobot/love.js GitHub repo
FROM node:18-alpine AS builder

# Install git and zip
RUN apk add --no-cache git zip findutils

# Clone Davidobot/love.js repository
WORKDIR /opt
RUN git clone --depth 1 https://github.com/Davidobot/love.js.git love.js-davidobot

# Install dependencies for the cloned love.js CLI tool
WORKDIR /opt/love.js-davidobot
RUN if [ -f package.json ]; then npm install; fi

# Set up the main application code and build game.love
WORKDIR /usr/src/app

# Copy all game source files (project root is the build context)
COPY . .

# Create the .love file more robustly
RUN mkdir -p /tmp/gamedata_for_love_file

# Copy all .lua files from current WORKDIR root to staging area
# Also copy main.lua and conf.lua explicitly to ensure they are present.
RUN find . -maxdepth 1 -name '*.lua' -exec cp -t /tmp/gamedata_for_love_file/ {} + 2>/dev/null || :
RUN cp main.lua /tmp/gamedata_for_love_file/main.lua
RUN cp conf.lua /tmp/gamedata_for_love_file/conf.lua
RUN if [ -f web_api.lua ]; then cp web_api.lua /tmp/gamedata_for_love_file/web_api.lua; fi

# Copy essential directories
RUN cp -R engine /tmp/gamedata_for_love_file/engine
RUN cp -R functions /tmp/gamedata_for_love_file/functions
RUN cp -R resources /tmp/gamedata_for_love_file/resources
RUN cp -R localization /tmp/gamedata_for_love_file/localization
# Add any other directories that are part of your game at the root level

# Create game.love
RUN cd /tmp/gamedata_for_love_file && zip -r /tmp/game.love . && cd /usr/src/app

# Run the cloned love.js CLI on the game.love
RUN node /opt/love.js-davidobot/index.js /tmp/game.love ./game_web -c --title Balatro -m 134217728

# Clean up temporary files
RUN rm -rf /tmp/gamedata_for_love_file /tmp/game.love


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
