# Ralph Loop — Librería R moderna para scraping de X/Twitter usando Lightpanda

Actuá como un **senior software engineer especializado en R, browser automation, scraping, CDP, Lightpanda, TypeScript/Node.js, sistemas distribuidos, testing y diseño de paquetes open source**.

Tu misión es **diseñar, implementar, ejecutar, probar, depurar y documentar una librería R moderna para recolectar datos de X/Twitter utilizando Lightpanda como navegador headless**, aprovechando las tecnologías más actuales disponibles.

No quiero solamente un análisis o un plan.

Quiero que **construyas realmente la librería**, ejecutes el código, pruebes distintas estrategias y avances iterativamente hasta obtener un MVP funcional y verificable.

Trabajá utilizando un **Ralph Loop autónomo**:

**OBSERVE → SELECT → IMPLEMENT → RUN → TEST → DIAGNOSE → FIX → REFACTOR → DOCUMENT → LOOP**

No consideres terminada la tarea hasta satisfacer los criterios de aceptación definidos al final.

---

# 1. OBJETIVO

Construir un paquete R mantenible, rápido y extensible para extraer datos de X/Twitter mediante Lightpanda.

Nombre provisional:

```text
xtweetsR
```

Podés cambiarlo si encontrás un nombre claramente mejor, pero no detengas el desarrollo por esto.

La experiencia ideal desde R debería ser aproximadamente:

```r
library(xtweetsR)

x <- x_session()

posts <- x_search(
  x,
  query = '"inteligencia artificial" lang:es',
  limit = 1000
)

posts
```

También:

```r
posts <- x_user_posts(
  x,
  username = "usuario",
  limit = 500
)
```

El resultado debe devolverse como estructuras compatibles de manera natural con:

```text
tibble
dplyr
tidyr
data.table
arrow
duckdb
```

La librería debe estar especialmente preparada para investigación en ciencias sociales computacionales y recolecciones de decenas de miles o cientos de miles de publicaciones.

---

# 2. INVESTIGACIÓN TÉCNICA INICIAL

Antes de decidir la arquitectura definitiva, investigá las versiones y capacidades ACTUALES de:

- Lightpanda
- repositorio oficial de Lightpanda
- Chrome DevTools Protocol
- Playwright
- Puppeteer
- playwright-core
- puppeteer-core
- WebSocket
- browser automation moderna
- paquetes R para WebSocket y CDP
- processx
- callr
- jsonlite
- httr2
- cli
- rlang
- testthat
- Arrow
- DuckDB

No asumas que APIs antiguas siguen funcionando.

Utilizá documentación oficial, repositorios y código fuente actual.

Cuando exista incertidumbre:

**hacé un experimento mínimo ejecutable.**

No decidas solamente a partir de documentación.

Registrar decisiones relevantes en:

```text
docs/architecture.md
```

---

# 3. PRINCIPIO ARQUITECTÓNICO

La API pública R debe estar desacoplada del mecanismo específico utilizado para controlar Lightpanda.

Evaluar experimentalmente tres estrategias.

## Estrategia A

```text
R
↓
WebSocket
↓
Chrome DevTools Protocol
↓
Lightpanda
```

## Estrategia B

```text
R
↓
Node.js / TypeScript sidecar
↓
Playwright / Puppeteer
↓
CDP
↓
Lightpanda
```

## Estrategia C

Arquitectura híbrida con backend intercambiable.

Hipótesis inicial recomendada:

```text
R package
   │
   ├── API pública
   ├── orchestration
   ├── parsing
   ├── normalization
   ├── persistence
   └── research data model
          │
          ▼
   Node / TypeScript sidecar
          │
          ▼
 playwright-core / puppeteer-core
          │
          ▼
         CDP
          │
          ▼
      Lightpanda
          │
          ▼
           X
```

No adoptar esta arquitectura dogmáticamente.

Construí pequeños prototipos y elegí según:

1. estabilidad;
2. performance;
3. control;
4. facilidad de debugging;
5. mantenibilidad;
6. capacidad de acceder a network events;
7. capacidad de manipular DOM;
8. capacidad de ejecutar JavaScript;
9. integración con R.

---

# 4. ABSTRACCIÓN DEL BROWSER

Diseñar desde el inicio una abstracción como:

```r
x_session(
  backend = "lightpanda",
  endpoint = NULL
)
```

La API pública no debe depender directamente de Lightpanda.

En el futuro debería poder soportar:

```r
backend = "lightpanda"
backend = "chromium"
backend = "remote-cdp"
```

sin modificar:

```r
x_search()
x_user_posts()
x_post()
x_thread()
```

---

# 5. LIGHTPANDA

Implementar inicialmente soporte para Lightpanda local.

Ejemplo conceptual:

```text
ws://127.0.0.1:9222
```

Investigar también Lightpanda Cloud y conexión remota mediante CDP.

Configuración mediante variables de entorno cuando corresponda:

```text
LPD_ENDPOINT
LPD_TOKEN
```

Nunca hardcodear secretos.

Crear funciones internas capaces de:

```text
start browser
connect browser
create context
create page
navigate
execute JavaScript
inspect DOM
intercept network
scroll
wait for events
close page
close browser
```

---

# 6. OBJETIVO PRINCIPAL: X/TWITTER

El objetivo inmediato es poder recolectar publicaciones desde:

## Search

```r
x_search()
```

## User timeline

```r
x_user_posts()
```

## Individual post

```r
x_post()
```

Posteriormente:

```r
x_thread()
x_replies()
x_quotes()
```

Priorizar una ruta vertical completa antes de agregar muchas funciones.

---

# 7. ESTRATEGIA DE EXTRACCIÓN

No depender exclusivamente de scraping HTML tradicional.

Investigar todas las capas de información disponibles durante la navegación.

Prioridad aproximada:

## Nivel 1 — Network

Inspeccionar tráfico de red mediante CDP.

Buscar:

- fetch;
- XHR;
- GraphQL;
- JSON;
- payloads estructurados;
- metadata;
- cursors;
- timeline responses;
- pagination tokens.

Determinar experimentalmente qué información recibe el navegador durante búsquedas y timelines.

Construir tooling interno para inspeccionar:

```text
request URL
method
headers
request payload
response status
response headers
response body
resource type
timing
```

Crear un modo de debugging:

```r
x_network_debug()
```

o equivalente.

---

# 8. NETWORK FIRST

Si los posts aparecen en respuestas JSON o estructuras equivalentes antes de renderizarse en el DOM, preferir esa fuente.

El parser de datos estructurados debe estar separado de la navegación.

Arquitectura:

```text
browser
   ↓
network events
   ↓
raw responses
   ↓
X parser
   ↓
normalizer
   ↓
canonical schema
   ↓
tibble
```

Guardar fixtures representativos para testing.

---

# 9. DOM FALLBACK

Cuando la información necesaria no esté disponible estructuradamente, usar DOM.

Priorizar selectores relativamente estables:

```text
article
data-testid
role
aria attributes
semantic structure
```

Centralizar selectores.

Por ejemplo:

```text
src/x/selectors.ts
```

Nunca dispersar docenas de selectores específicos de X por diferentes módulos.

---

# 10. PARSERS INDEPENDIENTES

Separar completamente:

```text
navigation
network capture
DOM capture
raw extraction
parsing
normalization
validation
storage
```

Ejemplo:

```text
search.ts
timeline.ts
network.ts
selectors.ts
parser.ts
normalize.ts
```

Los parsers deben poder ejecutarse contra fixtures sin iniciar Lightpanda.

---

# 11. EXPLORACIÓN DEL FRONTEND DE X

Crear herramientas internas para investigar la aplicación.

Ejemplos:

```r
x_debug_page()
x_debug_network()
x_debug_dom()
x_dump_network()
x_dump_html()
```

Permitir identificar:

- endpoints usados;
- estructuras JSON;
- nombres de operaciones GraphQL;
- cursores;
- objetos tweet/post;
- objetos user;
- metadata;
- pagination;
- respuestas al hacer scroll.

Guardar solamente muestras pequeñas necesarias para desarrollo y tests.

---

# 12. API PÚBLICA R

Diseñar inicialmente:

```r
x_session()
x_close()

x_search()
x_user()
x_user_posts()
x_post()

x_collect()
x_stream_scroll()

x_save()
x_read()

x_doctor()
```

Implementar primero:

```text
x_session()
x_search()
x_user_posts()
```

Luego extender.

---

# 13. x_search()

Objetivo de API:

```r
x_search(
  session,
  query,
  limit = Inf,
  since = NULL,
  until = NULL,
  lang = NULL,
  mode = c("latest", "top"),
  checkpoint = NULL,
  progress = interactive()
)
```

El algoritmo debe:

1. construir la búsqueda;
2. navegar;
3. esperar resultados;
4. comenzar captura;
5. extraer posts;
6. normalizar;
7. deduplicar;
8. hacer scroll;
9. detectar nuevas respuestas;
10. procesar cursores cuando existan;
11. continuar;
12. detenerse al alcanzar el objetivo.

---

# 14. SCROLL ENGINE

Construir un controlador de scroll robusto.

Mantener estado explícito:

```text
seen_post_ids
current_count
previous_count
no_new_data_cycles
scroll_position
last_post_id
last_cursor
elapsed_time
requests_seen
responses_parsed
```

El motor debe saber cuándo avanzar, cuándo esperar y cuándo terminar.

No usar bucles infinitos sin estado.

---

# 15. CURSORS Y PAGINACIÓN

Investigar especialmente si X utiliza cursors internos.

Si existen cursores disponibles en respuestas estructuradas:

- identificarlos;
- almacenarlos;
- versionarlos;
- estudiar cómo cambian;
- determinar su relación con infinite scroll.

La extracción no debe asumir que scrolling físico es siempre la única forma de paginación.

Diseñar:

```text
ScrollStrategy
CursorStrategy
NetworkPaginationStrategy
```

o abstracciones equivalentes si aportan valor real.

---

# 16. ESQUEMA CANÓNICO DE POSTS

Crear un schema interno explícito.

Campos iniciales:

```text
post_id
conversation_id

author_id
username
display_name

created_at
text
lang

reply_count
repost_count
like_count
quote_count
bookmark_count
view_count

is_reply
is_repost
is_quote

reply_to_post_id
quoted_post_id

url

hashtags
mentions
urls

media_type
media_urls

possibly_sensitive

collected_at
collection_query
collection_method
collector_version
```

Agregar campos útiles descubiertos durante investigación.

No eliminar datos disponibles sin una razón.

---

# 17. IDs

Todos los identificadores de X deben almacenarse como:

```r
character
```

Nunca:

```r
double
```

Evitar cualquier riesgo de pérdida de precisión.

---

# 18. ESTRUCTURA DE DATOS

Evaluar un modelo relacional:

```text
posts
users
media
hashtags
mentions
urls
collections
post_collections
```

La función sencilla:

```r
x_search()
```

puede devolver inicialmente una tabla de posts.

Pero internamente la arquitectura debe permitir relaciones múltiples.

---

# 19. DEDUPLICACIÓN

Clave principal:

```text
post_id
```

Nunca deduplicar por texto.

Un mismo post puede aparecer:

- varias veces durante scroll;
- en varias respuestas;
- en distintas consultas.

Mantener relación entre:

```text
post_id
collection_id
query
```

---

# 20. PROVENANCE

Cada corrida debe generar metadata.

```text
collection_id
started_at
finished_at
query
package_version
backend
lightpanda_version
parser_version
records
requests
responses
warnings
errors
```

Esto es particularmente importante para investigación reproducible.

---

# 21. CHECKPOINTS

Prioridad alta.

Ejemplo:

```r
x_search(
  session,
  query = "protesta",
  limit = 100000,
  checkpoint = "data/protestas"
)
```

No mantener 100.000 posts únicamente en RAM.

Persistir periódicamente.

Evaluar:

```text
Parquet
DuckDB
JSONL
```

Preferencia inicial:

```text
Parquet o DuckDB
```

CSV puede existir como formato de exportación, pero no como formato interno principal.

---

# 22. REANUDACIÓN

Una ejecución interrumpida debe poder retomarse.

Guardar:

```text
seen_post_ids
last_cursor
last_post_id
query
collection_id
records_collected
timestamps
```

Objetivo:

```r
x_search(
  session,
  query = "...",
  checkpoint = "data/protestas",
  resume = TRUE
)
```

---

# 23. STREAMING

Diseñar extracción incremental.

Conceptualmente:

```text
Browser
↓
Network events
↓
Parser
↓
Batch
↓
Normalizer
↓
Deduplicate
↓
Storage
```

No esperar al final para guardar todo.

Usar batches configurables.

Ejemplo:

```r
batch_size = 500
```

---

# 24. ARROW

Agregar soporte opcional para Parquet.

Ejemplo:

```r
x_save(
  posts,
  "posts.parquet"
)
```

Considerar particionamiento:

```text
year
month
collection_id
```

si resulta útil.

---

# 25. DUCKDB

Investigar DuckDB como almacenamiento de colecciones grandes.

Ejemplo conceptual:

```r
x_collect(
  ...,
  output = "duckdb",
  path = "tweets.duckdb"
)
```

Diseñar tablas indexables y consultas desde R.

---

# 26. PERFORMANCE

Lightpanda se elige precisamente para experimentar con browser automation más eficiente.

Medir realmente:

```text
startup time
navigation time
posts/minute
requests/sec
RAM
CPU
parsing time
storage throughput
```

Cuando sea posible comparar:

```text
Lightpanda
vs
Chromium headless
```

Guardar benchmarks en:

```text
benchmarks/
```

No asumir resultados.

Medir.

---

# 27. CONCURRENCIA

Una vez que el colector individual sea estable, investigar concurrencia.

Posibles escenarios:

```text
multiple queries
multiple users
multiple time ranges
multiple pages
```

Diseñar un scheduler simple.

No introducir concurrencia antes de tener un pipeline individual estable.

Prioridad:

```text
correct collector
↓
streaming collector
↓
checkpointing
↓
concurrency
```

---

# 28. ERRORES

Crear clases de errores claras.

Por ejemplo:

```text
LPD_CONNECTION_ERROR
CDP_ERROR
PAGE_LOAD_ERROR
NETWORK_ERROR
AUTH_REQUIRED
LAYOUT_CHANGED
PARSER_ERROR
CURSOR_ERROR
TIMEOUT
NO_NEW_DATA
UNSUPPORTED_PAGE
```

Desde R usar condiciones específicas cuando resulte conveniente.

No usar simplemente:

```text
stop("failed")
```

---

# 29. LOGGING

Usar `cli`.

Ejemplo:

```text
✓ Lightpanda conectado
✓ CDP conectado
→ abriendo X
→ búsqueda: protesta
→ 521 posts
→ 1,204 posts
→ 2,843 posts
→ checkpoint
→ 5,000 posts
✓ colección terminada
```

Permitir:

```r
quiet = TRUE
```

---

# 30. DIAGNÓSTICO

Implementar:

```r
x_doctor()
```

Salida esperada:

```text
R ................ OK
Node.js .......... OK
Lightpanda ....... OK
CDP .............. OK
Sidecar .......... OK
Network capture .. OK
X navigation ..... OK
```

También considerar:

```r
x_debug_session()
```

---

# 31. NODE/TYPESCRIPT SIDECAR

Si los experimentos muestran que TypeScript es la mejor opción, estructurar:

```text
inst/
  node/
    package.json
    tsconfig.json

    src/
      index.ts

      browser/
        browser.ts
        cdp.ts
        network.ts

      x/
        search.ts
        user.ts
        timeline.ts
        post.ts
        parser.ts
        selectors.ts
        normalize.ts
```

Usar TypeScript:

```text
strict = true
```

---

# 32. COMUNICACIÓN R ↔ NODE

Preferir un protocolo simple y robusto.

Evaluar:

```text
JSON Lines
JSON-RPC
stdin/stdout
named pipes
WebSocket local
```

Hipótesis inicial:

```text
R
↓
persistent Node process
↓
JSONL stdin/stdout
```

Cada mensaje debería tener:

```json
{
  "id": "...",
  "method": "...",
  "params": {}
}
```

Respuesta:

```json
{
  "id": "...",
  "result": {}
}
```

Errores:

```json
{
  "id": "...",
  "error": {
    "code": "...",
    "message": "..."
  }
}
```

Logs:

```text
stderr
```

Datos/protocolo:

```text
stdout
```

No mezclar ambos.

---

# 33. PROCESO PERSISTENTE

Evitar iniciar Node para cada post.

Crear un sidecar persistente mientras exista:

```r
x_session()
```

Conceptualmente:

```text
x_session()
    ↓
Node process
    ↓
Lightpanda connection
    ↓
browser context
```

Cerrar todo con:

```r
x_close()
```

---

# 34. X_SESSION

Diseñar una clase R.

Ejemplo:

```r
session <- x_session()

print(session)
```

Salida:

```text
<xtweets_session>
Backend: Lightpanda
Status: connected
Endpoint: localhost
Pages: 1
```

Puede utilizar:

```text
R6
environment
S3
```

Elegir la opción más simple y mantenible.

---

# 35. PAQUETE R

Seguir estándares actuales:

```text
DESCRIPTION
NAMESPACE
R/
man/
tests/testthat/
inst/
vignettes/
README.Rmd o README.qmd
NEWS.md
LICENSE
```

Usar:

```text
roxygen2
testthat edition 3
cli
processx
jsonlite
```

Agregar otras dependencias solamente cuando estén justificadas.

---

# 36. TESTS

Crear varios niveles.

## Unit tests

Para:

```text
post parsing
user parsing
dates
metrics
URLs
hashtags
mentions
media
IDs
normalization
deduplication
pagination
```

## Fixture tests

Guardar pequeños fragmentos reales necesarios para reproducir parsers.

## Browser integration tests

Crear páginas locales controladas.

## X integration tests

Crear tests específicos contra X.

Separarlos de los unit tests.

---

# 37. MOCK X

Crear una pequeña aplicación local que imite características necesarias.

Por ejemplo:

```text
test-server/
```

Debe simular:

- posts;
- infinite scroll;
- lazy loading;
- network JSON;
- cursors;
- posts duplicados;
- delayed responses;
- errores;
- cambios de DOM.

Esto permite desarrollar el motor sin depender continuamente de X.

---

# 38. NETWORK FIXTURES

Crear fixtures de respuestas estructuradas.

Ejemplo:

```text
tests/fixtures/network/
```

Los fixtures deben servir para probar parsers independientemente del browser.

---

# 39. DETECCIÓN DE CAMBIOS

El sistema debe detectar cuándo un parser deja de reconocer respuestas.

Por ejemplo:

```text
expected post object not found
unknown timeline structure
cursor missing
unexpected response schema
```

Cuando esto ocurra:

- guardar información diagnóstica;
- emitir error útil;
- indicar parser afectado.

---

# 40. VERSIONADO DE PARSERS

Asignar versión interna:

```text
parser_version
schema_version
```

Así una colección podrá registrar:

```text
xtweetsR 0.1.0
parser 3
schema 2
```

---

# 41. GITHUB ACTIONS

Configurar CI.

Pipeline:

```text
R CMD check
testthat
TypeScript compile
Node tests
lint
```

Los tests que dependan de acceso externo pueden configurarse separadamente.

---

# 42. DOCUMENTACIÓN

Crear README práctico.

Primer ejemplo:

```r
library(xtweetsR)

x <- x_session()

posts <- x_search(
  x,
  query = '"paro general"',
  limit = 1000
)

posts
```

Mostrar:

```r
posts |>
  dplyr::count(username, sort = TRUE)
```

Crear vignettes:

```text
getting-started
searching-x
user-timelines
large-collections
storage
architecture
```

---

# 43. CASO DE USO PRINCIPAL

Pensar particularmente en investigación social.

Consultas típicas:

```text
protesta
huelga
manifestación
movilización
conflicto laboral
paro
piquete
```

Ejemplo:

```r
tweets <- x_search(
  x,
  query = '("paro" OR "huelga") lang:es',
  since = as.Date("2026-01-01"),
  until = as.Date("2026-02-01"),
  limit = 10000,
  checkpoint = "data/huelgas"
)
```

Objetivo posterior:

analizar estos datos con:

```text
quanteda
tidytext
igraph
network
sf
arrow
duckdb
LLMs
```

---

# 44. METADATA PARA INVESTIGACIÓN

Cada observación debe poder vincularse con su colección.

Guardar:

```text
collection_id
query
collected_at
collector_version
```

Cada colección debe permitir reconstruir:

```text
qué se buscó
cuándo
cómo
con qué versión
cuántos posts aparecieron
qué errores ocurrieron
```

---

# 45. NO SOBREINGENIERÍA

Trabajar mediante vertical slices.

## Iteración 1

```text
R
↓
Node/CDP
↓
Lightpanda
↓
local test page
↓
tibble
```

## Iteración 2

```text
Lightpanda
↓
X
↓
capturar HTML
```

## Iteración 3

```text
Lightpanda
↓
X
↓
capturar network
```

## Iteración 4

```text
identificar posts
↓
parser
↓
tibble
```

## Iteración 5

```text
search
↓
scroll
↓
multiple posts
```

## Iteración 6

```text
cursor detection
↓
pagination
```

## Iteración 7

```text
deduplication
↓
limit
```

## Iteración 8

```text
incremental storage
↓
checkpoints
```

## Iteración 9

```text
resume
```

## Iteración 10

```text
optimization
```

No construir diez abstracciones antes de conseguir una extracción end-to-end.

---

# 46. RALPH LOOP

Después de cada iteración:

## OBSERVE

Revisar:

```text
code
tests
logs
errors
TODOs
git diff
architecture
```

## SELECT

Elegir el problema que actualmente más impide llegar al MVP.

Trabajar sobre un cuello de botella principal por ciclo.

## IMPLEMENT

Implementar el cambio mínimo que produzca progreso observable.

## RUN

Ejecutar realmente el código.

## TEST

Ejecutar los tests relevantes.

## DIAGNOSE

Si algo falla:

```text
reproduce
isolate
inspect
identify root cause
fix
regression test
```

No ocultar fallos mediante `tryCatch()` genérico.

## REFACTOR

Con tests verdes:

```text
remove duplication
improve names
improve types
simplify
reduce coupling
```

## DOCUMENT

Actualizar:

```text
README
architecture
TODO
RALPH_PROGRESS.md
```

## LOOP

Volver inmediatamente a OBSERVE.

---

# 47. RALPH_PROGRESS.md

Mantener obligatoriamente:

```markdown
# Ralph Progress

## Estado actual

...

## Último ciclo

...

## Funciona

- ...

## No funciona todavía

- ...

## Tests

- ...

## Descubrimientos sobre X

- ...

## Descubrimientos sobre Lightpanda

- ...

## Decisiones arquitectónicas

- ...

## Performance

- ...

## Próximo cuello de botella

...
```

Actualizarlo después de cada ciclo significativo.

---

# 48. PRIORIDADES

Ante cualquier conflicto:

```text
1. extracción funcional
2. integridad de datos
3. reproducibilidad
4. arquitectura desacoplada
5. recuperación ante errores
6. performance
7. API R limpia
8. documentación
9. features adicionales
```

---

# 49. PRINCIPIOS DE IMPLEMENTACIÓN

No:

- crear un único script gigante;
- mezclar browser automation con parsing;
- mezclar parsing con almacenamiento;
- usar selectores CSS por todo el proyecto;
- almacenar IDs como doubles;
- perder progreso si el proceso se interrumpe;
- depender exclusivamente del DOM;
- asumir cómo funciona X sin observar el tráfico real;
- asumir que scrolling físico es la única paginación;
- agregar Selenium sin demostrar que es necesario;
- agregar dependencias innecesarias;
- afirmar que algo funciona sin ejecutarlo.

Sí:

- experimentar;
- medir;
- inspeccionar network;
- usar CDP;
- crear fixtures;
- testear parsers;
- persistir incrementalmente;
- registrar provenance;
- desacoplar componentes.

---

# 50. INVESTIGACIÓN NETWORK ES PRIORITARIA

Antes de invertir demasiado tiempo en scraping DOM, comprobar qué ocurre al realizar:

```text
X search
user timeline
open post
scroll timeline
```

Capturar todas las respuestas relevantes.

Crear un pequeño programa de exploración capaz de mostrar algo como:

```text
[XHR] 200 ...
[fetch] 200 ...
[graphql] ...
[json] ...
```

Identificar cuáles contienen:

```text
post IDs
text
users
timestamps
metrics
cursors
```

A partir de esa investigación decidir el extractor principal.

---

# 51. CRITERIOS DE ACEPTACIÓN DEL MVP

No declarar terminado el MVP hasta demostrar mediante ejecución real que:

1. Existe un paquete R instalable.
2. `x_session()` funciona.
3. R puede iniciar o conectarse a Lightpanda.
4. Existe comunicación estable R ↔ browser backend.
5. Lightpanda puede cargar una página dinámica.
6. Se pueden ejecutar scripts JavaScript.
7. Se pueden observar eventos de red.
8. Se puede navegar a X.
9. Se puede abrir una búsqueda de X.
10. Se pueden identificar posts.
11. `x_search()` devuelve múltiples posts.
12. Los resultados se devuelven como `tibble`.
13. `post_id` es `character`.
14. Existe scroll incremental.
15. Existe deduplicación por `post_id`.
16. Existe un criterio determinista de terminación.
17. `limit` funciona.
18. Existe persistencia incremental.
19. Existe checkpoint.
20. Una ejecución puede reanudarse.
21. Los parsers pueden probarse usando fixtures.
22. Existen unit tests.
23. Existen integration tests.
24. `R CMD check` no presenta errores.
25. Existe `x_doctor()`.
26. README contiene un ejemplo real.
27. La arquitectura permite cambiar el backend sin modificar la API pública principal.

---

# 52. SEGUNDA ETAPA

Una vez alcanzado el MVP investigar mejoras como:

```text
parallel searches
multiple sessions
query partitioning
date partitioning
distributed collection
Arrow datasets
DuckDB collections
streaming interfaces
async R API
progress bars
recovery
automatic parser diagnostics
benchmarking
```

No comenzar estas optimizaciones antes del MVP.

---

# 53. ENTREGABLES

Al finalizar deben existir:

```text
paquete R funcional
Node/TypeScript sidecar si corresponde
Lightpanda integration
CDP integration
x_session()
x_search()
x_user_posts()
x_doctor()
network inspector
parsers
fixtures
unit tests
integration tests
checkpoints
resume
README
vignettes
CI
architecture.md
RALPH_PROGRESS.md
benchmark inicial
```

---

# 54. INSTRUCCIÓN FINAL

Comenzá inspeccionando el repositorio.

Si el repositorio está vacío:

1. inicializá el paquete R;
2. inicializá el sidecar si es necesario;
3. comprobá que Lightpanda esté disponible;
4. construí el experimento mínimo R → Lightpanda;
5. ejecutalo;
6. corregí errores;
7. avanzá hacia X.

No me entregues solamente recomendaciones.

**Programá. Ejecutá. Inspeccioná. Testeá. Corregí.**

Cuando una estrategia falle, no te detengas inmediatamente.

Investigá la causa raíz y probá una alternativa técnicamente razonable.

Cuando exista incertidumbre sobre cómo funciona X:

**inspeccioná el comportamiento real del navegador, especialmente CDP y network traffic.**

Cuando exista incertidumbre sobre Lightpanda:

**creá un experimento mínimo reproducible.**

No supongas.

Medí.

No declares funcional algo que no hayas ejecutado.

Continuá el Ralph Loop hasta alcanzar el MVP verificable o hasta identificar una limitación técnica concreta y reproducible que requiera una decisión arquitectónica diferente.
