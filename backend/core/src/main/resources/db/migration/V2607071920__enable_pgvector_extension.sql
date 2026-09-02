-- V2607071920__enable_pgvector_extension.sql
--
-- Task 1.6 — Enable pgvector for Ask AI hybrid retrieval embeddings.
-- Per Team E backlog and Hybrid Retrieval Scope design (1536-dim vectors).
--
-- Requires PostgreSQL with pgvector installed (local: pgvector/pgvector Docker image).
-- Production: Aurora PostgreSQL 15+ with the vector extension enabled before this runs.
-- Related: Task 1.5 retrieval_index_chunk.embedding column.

CREATE
EXTENSION IF NOT EXISTS vector;

COMMENT
ON EXTENSION vector IS
    'pgvector extension for Ask AI semantic retrieval (Task 1.6). Stores 1536-dim embeddings on retrieval_index_chunk.';
