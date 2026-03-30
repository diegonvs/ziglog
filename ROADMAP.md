# Roadmap: paridade com Pino

## Schema do log

Pino emite campos adicionais em cada entrada JSONL. Estado atual do ziglog:

| Campo    | Pino              | ziglog       | Status |
|----------|-------------------|--------------|--------|
| `msg`    | string            | `msg` string | done   |
| `time`   | ms desde epoch    | `ts` segundos | parcial — unidade diferente |
| `level`  | número (10–60)    | ausente      | todo   |
| `pid`    | PID do processo   | ausente      | todo   |
| `hostname` | nome da máquina | ausente      | todo   |

## Features

### Níveis de log

- [x] Definir os seis níveis: `trace` (10), `debug` (20), `info` (30), `warn` (40), `error` (50), `fatal` (60)
- [x] Gravar campo `level` no JSONL ao ingerir
- [x] `ziglog find --level <nivel>` filtra por nível mínimo
- [x] Coloração no `find` e `tail` baseada no campo `level` (em vez de keyword match)

### Filtragem por tempo

- [x] `ziglog find --since <duração>` (ex: `5m`, `1h`, `2d`)
- [x] `ziglog find --until <duração>` ou timestamp absoluto

### Schema

- [ ] Mudar `ts` de segundos para milissegundos (alinhamento com Pino)
- [ ] Adicionar `pid` ao schema
- [ ] Adicionar `hostname` ao schema

### Contexto persistente

- [ ] Suporte a campos extras via stdin estruturado (JSON passado direto)
- [ ] Ou: flag `--field key=value` no `start` para injetar campos fixos em todas as entradas

### Segurança

- [ ] `ziglog start --redact <campo>` mascara campos sensíveis (ex: `password`, `token`)

### Rotação de arquivo

- [ ] Rotação por tamanho (ex: `--max-size 100mb`)
- [ ] Rotação por tempo (ex: diária)
- [ ] Manter N arquivos de backup

## O que ziglog tem que Pino não tem nativamente

- `ziglog find` — busca no arquivo de log (Pino delega a ferramentas externas)
- `ziglog tail` com kqueue/inotify nativos (Pino depende de `tail -f` ou libs externas)
