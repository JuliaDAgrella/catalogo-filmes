-- init.sql — execute no RDS após criar a instância
CREATE DATABASE IF NOT EXISTS catalogo_filmes;
USE catalogo_filmes;

CREATE TABLE IF NOT EXISTS filmes (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  titulo      VARCHAR(255) NOT NULL,
  diretor     VARCHAR(255) NOT NULL,
  ano         YEAR        NOT NULL,
  genero      VARCHAR(100) NOT NULL,
  sinopse     TEXT,
  nota        DECIMAL(3,1) CHECK (nota BETWEEN 0 AND 10),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Dados de exemplo
INSERT INTO filmes (titulo, diretor, ano, genero, sinopse, nota) VALUES
('O Poderoso Chefão',  'Francis Ford Coppola', 1972, 'Crime/Drama',  'A história da família mafiosa Corleone.', 9.2),
('Interstellar',       'Christopher Nolan',     2014, 'Ficção Científica', 'Uma equipe de astronautas viaja além da galáxia.', 8.7),
('Parasita',           'Bong Joon-ho',          2019, 'Thriller',    'Duas famílias de classes opostas se entrechocam.', 8.5),
('Clube da Luta',      'David Fincher',         1999, 'Drama/Thriller', 'Um homem insatisfeito funda um clube de luta clandestino.', 8.8);
