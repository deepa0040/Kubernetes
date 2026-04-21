import express from "express";
import pg from "pg";

const app = express();
app.use(express.json());

const pool = new pg.Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// Create table on startup
pool.query(`
  CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
  )
`);

app.get("/api/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ message: "API healthy — DB connected" });
  } catch {
    res.status(500).json({ message: "DB unreachable" });
  }
});

// Get all items
app.get("/api/items", async (_req, res) => {
  try {
    const result = await pool.query("SELECT * FROM items ORDER BY created_at DESC");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Insert item
app.post("/api/items", async (req, res) => {
  const { name } = req.body;
  if (!name?.trim()) return res.status(400).json({ error: "Name is required" });
  try {
    const result = await pool.query(
      "INSERT INTO items (name) VALUES ($1) RETURNING *",
      [name.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete item
app.delete("/api/items/:id", async (req, res) => {
  try {
    await pool.query("DELETE FROM items WHERE id = $1", [req.params.id]);
    res.json({ message: "Deleted" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(5000, () => console.log("API running on :5000"));