// src/routes/filmes.js
const express = require('express');
const router  = express.Router();
const { body, param, validationResult } = require('express-validator');
const db = require('../config/database');

// ── Helpers ────────────────────────────────────────────────
function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({ errors: errors.array() });
  }
  next();
}

const filmeRules = [
  body('titulo').notEmpty().withMessage('título obrigatório'),
  body('diretor').notEmpty().withMessage('diretor obrigatório'),
  body('ano').isInt({ min: 1888, max: new Date().getFullYear() }).withMessage('ano inválido'),
  body('genero').notEmpty().withMessage('gênero obrigatório'),
  body('nota').optional().isFloat({ min: 0, max: 10 }).withMessage('nota deve ser entre 0 e 10'),
];

// ── GET /items — listar todos ──────────────────────────────
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.execute(
      'SELECT * FROM filmes ORDER BY created_at DESC'
    );
    res.json({ total: rows.length, filmes: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro interno ao listar filmes' });
  }
});

// ── GET /items/:id — buscar por id ─────────────────────────
router.get('/:id',
  param('id').isInt().withMessage('id deve ser inteiro'),
  validate,
  async (req, res) => {
    try {
      const [rows] = await db.execute(
        'SELECT * FROM filmes WHERE id = ?', [req.params.id]
      );
      if (rows.length === 0) {
        return res.status(404).json({ error: 'Filme não encontrado' });
      }
      res.json(rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'Erro interno ao buscar filme' });
    }
  }
);

// ── POST /items — criar ────────────────────────────────────
router.post('/', filmeRules, validate, async (req, res) => {
  const { titulo, diretor, ano, genero, sinopse, nota } = req.body;
  try {
    const [result] = await db.execute(
      'INSERT INTO filmes (titulo, diretor, ano, genero, sinopse, nota) VALUES (?, ?, ?, ?, ?, ?)',
      [titulo, diretor, ano, genero, sinopse || null, nota || null]
    );
    res.status(201).json({
      message: 'Filme criado com sucesso',
      id: result.insertId,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro interno ao criar filme' });
  }
});

// ── PUT /items/:id — atualizar ─────────────────────────────
router.put('/:id',
  [param('id').isInt().withMessage('id deve ser inteiro'), ...filmeRules],
  validate,
  async (req, res) => {
    const { titulo, diretor, ano, genero, sinopse, nota } = req.body;
    try {
      const [result] = await db.execute(
        `UPDATE filmes
         SET titulo=?, diretor=?, ano=?, genero=?, sinopse=?, nota=?
         WHERE id=?`,
        [titulo, diretor, ano, genero, sinopse || null, nota || null, req.params.id]
      );
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: 'Filme não encontrado' });
      }
      res.json({ message: 'Filme atualizado com sucesso' });
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'Erro interno ao atualizar filme' });
    }
  }
);

// ── DELETE /items/:id — remover ────────────────────────────
router.delete('/:id',
  param('id').isInt().withMessage('id deve ser inteiro'),
  validate,
  async (req, res) => {
    try {
      const [result] = await db.execute(
        'DELETE FROM filmes WHERE id = ?', [req.params.id]
      );
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: 'Filme não encontrado' });
      }
      res.json({ message: 'Filme removido com sucesso' });
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'Erro interno ao remover filme' });
    }
  }
);

module.exports = router;
