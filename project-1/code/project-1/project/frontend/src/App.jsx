import { useEffect, useState } from "react";

export default function App() {
  const [items, setItems]   = useState([]);
  const [name, setName]     = useState("");
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);

  const fetchItems = async () => {
    const res = await fetch("/api/items");
    const data = await res.json();
    setItems(data);
  };

  useEffect(() => { fetchItems(); }, []);

  const handleSubmit = async () => {
    if (!name.trim()) return setStatus("Please enter a name.");
    setLoading(true);
    const res = await fetch("/api/items", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
    if (res.ok) {
      setName("");
      setStatus("Item added!");
      await fetchItems();
    } else {
      const err = await res.json();
      setStatus(err.error || "Failed to add item.");
    }
    setLoading(false);
    setTimeout(() => setStatus(""), 3000);
  };

  const handleDelete = async (id) => {
    await fetch(`/api/items/${id}`, { method: "DELETE" });
    await fetchItems();
  };

  return (
    <div style={styles.page}>
      <div style={styles.card}>
        <h1 style={styles.title}>Items Manager</h1>
        <p style={styles.subtitle}>Data stored in PostgreSQL</p>

        {/* Insert form */}
        <div style={styles.form}>
          <input
            style={styles.input}
            type="text"
            placeholder="Enter item name..."
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSubmit()}
          />
          <button style={styles.btn} onClick={handleSubmit} disabled={loading}>
            {loading ? "Adding..." : "Add Item"}
          </button>
        </div>

        {status && <p style={styles.status}>{status}</p>}

        {/* Items list */}
        {items.length === 0 ? (
          <p style={styles.empty}>No items yet. Add one above.</p>
        ) : (
          <ul style={styles.list}>
            {items.map((item) => (
              <li key={item.id} style={styles.listItem}>
                <div>
                  <span style={styles.itemName}>{item.name}</span>
                  <span style={styles.itemMeta}>
                    #{item.id} · {new Date(item.created_at).toLocaleString()}
                  </span>
                </div>
                <button
                  style={styles.deleteBtn}
                  onClick={() => handleDelete(item.id)}
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

const styles = {
  page: {
    minHeight: "100vh",
    background: "#f0f2f5",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontFamily: "sans-serif",
    padding: "24px",
  },
  card: {
    background: "#fff",
    borderRadius: "12px",
    padding: "32px",
    width: "100%",
    maxWidth: "560px",
    boxShadow: "0 4px 24px rgba(0,0,0,0.08)",
  },
  title:    { margin: "0 0 4px", fontSize: "24px", fontWeight: 600 },
  subtitle: { margin: "0 0 24px", color: "#888", fontSize: "14px" },
  form:     { display: "flex", gap: "8px", marginBottom: "8px" },
  input: {
    flex: 1,
    padding: "10px 14px",
    borderRadius: "8px",
    border: "1px solid #ddd",
    fontSize: "15px",
    outline: "none",
  },
  btn: {
    padding: "10px 18px",
    background: "#4f46e5",
    color: "#fff",
    border: "none",
    borderRadius: "8px",
    fontSize: "15px",
    cursor: "pointer",
    fontWeight: 500,
  },
  status:   { fontSize: "13px", color: "#4f46e5", marginBottom: "8px" },
  empty:    { color: "#aaa", textAlign: "center", padding: "32px 0" },
  list:     { listStyle: "none", margin: "16px 0 0", padding: 0 },
  listItem: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "12px 0",
    borderBottom: "1px solid #f0f0f0",
  },
  itemName: { display: "block", fontWeight: 500, fontSize: "15px" },
  itemMeta: { display: "block", fontSize: "12px", color: "#aaa", marginTop: "2px" },
  deleteBtn: {
    padding: "6px 12px",
    background: "#fee2e2",
    color: "#dc2626",
    border: "none",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "13px",
    fontWeight: 500,
  },
};