const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const port = process.env.PORT || 3000;

// Directory where love.js output (packaged game) will be stored
const gameDir = path.join(__dirname, 'game_web');

// Middleware to serve static files from the love.js output directory
app.use(express.static(gameDir));
app.use(express.json()); // Middleware to parse JSON bodies

// Route to serve the main game page
app.get('/', (req, res) => {
    const indexPath = path.join(gameDir, 'index.html');
    if (fs.existsSync(indexPath)) {
        res.sendFile(indexPath);
    } else {
        // If index.html doesn't exist in gameDir, it means the game hasn't been packaged yet.
        // Send a placeholder message or handle as an error.
        // For now, also serve the top-level index.html if gameDir/index.html is missing.
        const rootIndexPath = path.join(__dirname, 'index.html');
        if (fs.existsSync(rootIndexPath)) {
            res.sendFile(rootIndexPath);
        } else {
            res.status(404).send('Game not found. Please ensure the game has been packaged into the game_web directory.');
        }
    }
});

// API routes for saving/loading game data
const SAVES_DIR = path.join(__dirname, 'saves');
if (!fs.existsSync(SAVES_DIR)){
    fs.mkdirSync(SAVES_DIR, { recursive: true });
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
    console.log(`Serving game from: ${gameDir}`);
    if (!fs.existsSync(gameDir) || !fs.existsSync(path.join(gameDir, 'index.html'))) {
        console.warn(`Warning: The directory ${gameDir} or ${path.join(gameDir, 'index.html')} does not exist yet.`);
        console.warn(`Make sure to run the love.js packaging command (e.g., 'npx love.js . game_web -c')`);
        console.warn(`and ensure the output is placed in the 'game_web' directory.`);
    }
});
