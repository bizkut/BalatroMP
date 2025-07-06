# Stage 1: Build the .love file
FROM alpine AS lovefile_builder

# Install zip and git
RUN apk add --no-cache zip git

# Clone the game repository (or copy files if Docker context is the game repo)
# For this Dockerfile, we assume the context IS the game repository.
WORKDIR /tmp/balatro-game-source
COPY . .

# Clone the 2dengine/love.js repository to get fetch.lua
WORKDIR /tmp
RUN git clone --depth 1 https://github.com/2dengine/love.js.git lovejs_2dengine
# Copy fetch.lua to the root of our game source, so it gets included in game.love
RUN cp /tmp/lovejs_2dengine/fetch.lua /tmp/balatro-game-source/fetch.lua

# Create the .love file from the game source (which now includes fetch.lua)
WORKDIR /tmp/balatro-game-source
RUN zip -r /tmp/game.love .

# Stage 2: Prepare the 2dengine/love.js player files
FROM alpine AS player_builder

RUN apk add --no-cache git

WORKDIR /usr/src
# Clone the specific love.js player repository
RUN git clone --depth 1 https://github.com/2dengine/love.js.git lovejs_player_files
# We'll copy from this stage later. This keeps the final image cleaner.

# Stage 3: Setup the Node.js server and serve the packaged game
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package.json and install runtime dependencies
COPY package.json ./
COPY package-lock.json* ./
RUN npm install --omit=dev --ignore-scripts

# Copy the server application files
COPY server.js ./
COPY web_api.lua ./
# The game's specific index.html (if any for instructions/etc) is less important now,
# as the 2dengine/love.js index.html will be the entry point.
# COPY index.html ./

# Copy the .love file from the lovefile_builder stage
COPY --from=lovefile_builder /tmp/game.love ./game.love

# Copy the 2dengine/love.js player files from the player_builder stage
COPY --from=player_builder /usr/src/lovejs_player_files/index.html ./lovejs_player/
COPY --from=player_builder /usr/src/lovejs_player_files/player.js ./lovejs_player/
COPY --from=player_builder /usr/src/lovejs_player_files/player.min.js ./lovejs_player/
COPY --from=player_builder /usr/src/lovejs_player_files/style.css ./lovejs_player/
COPY --from=player_builder /usr/src/lovejs_player_files/nogame.love ./lovejs_player/
# Copy one specific LÖVE engine version, e.g., 11.5
# Adjust if a different version is desired.
COPY --from=player_builder /usr/src/lovejs_player_files/11.5 ./lovejs_player/11.5
# If you need other versions (11.3, 11.4), copy them similarly.
# COPY --from=player_builder /usr/src/lovejs_player_files/11.3 ./lovejs_player/11.3
# COPY --from=player_builder /usr/src/lovejs_player_files/11.4 ./lovejs_player/11.4


# Create and set permissions for the saves directory
RUN mkdir -p saves && chown -R node:node /usr/src/app/saves \
    && chown -R node:node /usr/src/app/lovejs_player \
    && chown node:node /usr/src/app/game.love

# Expose Port
EXPOSE 3000

# Start Command
CMD [ "npm", "start" ]
