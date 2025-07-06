const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const port = process.env.PORT || 3000;

// Directory for the 2dengine/love.js player files
const playerDir = path.join(__dirname, 'lovejs_player');
// Location of the game.love file
const gameFile = path.join(__dirname, 'game.love'); // Placed at app root by Dockerfile

app.use(express.json()); // Middleware to parse JSON bodies

// Middleware to set required HTTP headers for love.js (2dengine version)
app.use((req, res, next) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    next();
});

// Serve static files from the lovejs_player directory (e.g., player.js, LÖVE engine versions)
app.use('/lovejs_player', express.static(playerDir));

// Serve the game.love file itself if requested directly (e.g. by player.js)
// The player.js will fetch it relative to its own path or via absolute path.
// Let's make game.love available at a predictable path e.g. /games/game.love
app.get('/game.love', (req, res) => {
    if (fs.existsSync(gameFile)) {
        res.sendFile(gameFile);
    } else {
        res.status(404).send('game.love not found on server.');
    }
});
// Also make it available if player.js tries to fetch from /games/ directory
app.get('/games/game.love', (req, res) => {
    if (fs.existsSync(gameFile)) {
        res.sendFile(gameFile);
    } else {
        res.status(404).send('game.love not found in /games/.');
    }
});


// Main route to serve the game player
// This will redirect to the love.js player's index.html with the game specified
app.get('/', (req, res) => {
    const playerIndexPath = path.join(playerDir, 'index.html');
    if (fs.existsSync(playerIndexPath)) {
        // Redirect to the player, instructing it to load game.love from the root
        // player.js will try to load game from ?g= parameter.
        // If game.love is at /usr/src/app/game.love, and player files are in /usr/src/app/lovejs_player
        // player.js (inside lovejs_player) will look for `../game.love` if g=../game.love
        // or `/game.love` if g=/game.love
        res.redirect('/lovejs_player/index.html?g=../game.love&v=11.5');
    } else {
        res.status(404).send('Love.js player not found. Please ensure player files are in lovejs_player directory.');
    }
});

// API routes for saving/loading game data
const SAVES_DIR = path.join(__dirname, 'saves');
if (!fs.existsSync(SAVES_DIR)){
    fs.mkdirSync(SAVES_DIR, { recursive: true }); // Ensure SAVES_DIR is defined
}

// Save game data
app.post('/api/save', (req, res) => {
    const { id, data } = req.body; // Expect an 'id' (e.g., 'run', 'profile1_meta') and 'data' (the STR_PACKed string)
    if (!id || data === undefined) {
        return res.status(400).json({ success: false, message: 'Missing id or data in save request.' });
    }

    // Sanitize the id to prevent directory traversal issues, though it should be a simple key.
    const safeId = path.basename(id);
    const saveFilePath = path.join(SAVES_DIR, `${safeId}.json`);

    // The data received is already a string (STR_PACKed), so we store it within a JSON structure.
    const contentToStore = JSON.stringify({ id: safeId, data: data }, null, 2);

    fs.writeFile(saveFilePath, contentToStore, (err) => {
        if (err) {
            console.error(`Failed to save game for id '${safeId}':`, err);
            return res.status(500).json({ success: false, message: `Failed to save game for id '${safeId}'.` });
        }
        console.log(`Game saved successfully to: ${saveFilePath}`);
        res.json({ success: true, message: `Game for id '${safeId}' saved successfully.` });
    });
});

// Load game data
app.get('/api/load', (req, res) => {
    const { id } = req.query; // Expect 'id' as a query parameter
    if (!id) {
        return res.status(400).json({ success: false, message: 'Missing id in load request.' });
    }

    const safeId = path.basename(id);
    const saveFilePath = path.join(SAVES_DIR, `${safeId}.json`);

    fs.readFile(saveFilePath, 'utf8', (err, fileContent) => {
        if (err) {
            if (err.code === 'ENOENT') {
                console.log(`No save file found for id '${safeId}'.`);
                // Return success:true, data:null as per web_api.lua expectation
                return res.json({ success: true, data: null, message: `No save file found for id '${safeId}'.` });
            }
            console.error(`Failed to load game for id '${safeId}':`, err);
            return res.status(500).json({ success: false, message: `Failed to load game for id '${safeId}'.` });
        }
        try {
            // The file content is a JSON string like { "id": "...", "data": "STR_PACK_output" }
            const parsedContent = JSON.parse(fileContent);
            console.log(`Game loaded successfully from: ${saveFilePath}`);
            // web_api.lua expects an object that has a 'data' field containing the STR_PACK string.
            res.json({ success: true, data: parsedContent, message: `Game for id '${safeId}' loaded successfully.` });
        } catch (parseErr) {
            console.error(`Failed to parse save data for id '${safeId}':`, parseErr);
            return res.status(500).json({ success: false, message: `Failed to parse save data for id '${safeId}'.` });
        }
    });
});

app.listen(port, () => {
    console.log(`Server listening at http://localhost:${port}`);
    console.log(`Serving LÖVE game player from: ${playerDir}`);
    console.log(`Game file expected at: ${gameFile}`);
    if (!fs.existsSync(playerDir) || !fs.existsSync(path.join(playerDir, 'index.html'))) {
        console.warn(`Warning: The directory ${playerDir} or its index.html does not exist yet.`);
    }
    if (!fs.existsSync(gameFile)) {
        console.warn(`Warning: The game file ${gameFile} does not exist yet.`);
    }
});
