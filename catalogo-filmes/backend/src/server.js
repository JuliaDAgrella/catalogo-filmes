// src/server.js
require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const filmesRouter = require('./routes/filmes');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Middlewares ────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// ── Health check ───────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ── Rotas CRUD ─────────────────────────────────────────────
// API Gateway encaminha /items* para este serviço
app.use('/items', filmesRouter);

// ── 404 genérico ───────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Rota não encontrada' }));

// ── Start ──────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅ Backend rodando na porta ${PORT}`);
});
