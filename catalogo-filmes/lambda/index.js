// lambda/report/index.js
// Recebe GET /report via API Gateway → consome /items do back-end → retorna JSON com estatísticas
// IMPORTANTE: NÃO acessa o RDS diretamente.

const https = require('https');
const http  = require('http');

// URL interna do back-end (configurada como variável de ambiente no Lambda)
const API_URL = process.env.BACKEND_URL || 'http://localhost:3000';

function fetchItems() {
  return new Promise((resolve, reject) => {
    const lib = API_URL.startsWith('https') ? https : http;
    lib.get(`${API_URL}/items`, (res) => {
      let data = '';
      res.on('data', chunk => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

exports.handler = async (_event) => {
  try {
    const { filmes = [] } = await fetchItems();

    if (filmes.length === 0) {
      return response(200, { message: 'Nenhum filme cadastrado ainda.', stats: {} });
    }

    // ── Estatísticas ──────────────────────────────────────
    const notas  = filmes.map(f => Number(f.nota)).filter(n => !isNaN(n));
    const total  = filmes.length;
    const media  = notas.length ? (notas.reduce((a, b) => a + b, 0) / notas.length).toFixed(2) : null;
    const maior  = notas.length ? Math.max(...notas) : null;
    const menor  = notas.length ? Math.min(...notas) : null;

    // Por gênero
    const porGenero = filmes.reduce((acc, f) => {
      acc[f.genero] = (acc[f.genero] || 0) + 1;
      return acc;
    }, {});

    // Por década
    const porDecada = filmes.reduce((acc, f) => {
      const decada = `${Math.floor(f.ano / 10) * 10}s`;
      acc[decada] = (acc[decada] || 0) + 1;
      return acc;
    }, {});

    const melhorFilme = filmes.reduce((best, f) =>
      Number(f.nota) > Number(best.nota || 0) ? f : best, filmes[0]);

    return response(200, {
      gerado_em: new Date().toISOString(),
      stats: {
        total_filmes:  total,
        nota_media:    Number(media),
        nota_maxima:   maior,
        nota_minima:   menor,
        melhor_filme:  { titulo: melhorFilme.titulo, nota: melhorFilme.nota },
        por_genero:    porGenero,
        por_decada:    porDecada,
      },
    });
  } catch (err) {
    console.error('Erro no Lambda /report:', err);
    return response(500, { error: 'Falha ao gerar relatório', detalhe: err.message });
  }
};

function response(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}
