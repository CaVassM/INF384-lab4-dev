# Respuestas · Laboratorio 4
Alumno: [código]
Presupuesto: [ ] min  Métrica DORA: [ ]

## Parte 1 · Diagnóstico
Nota sobre las horas: los fragmentos de log están en UTC; la hora Lima (UTC−5) se indica entre paréntesis o como "Lima". Todos los runs son del 29/10/2026, posteriores a las 16:00 Lima. Los 5 commits se subieron por separado a main, así que cada uno disparó su propio run; el run 1 (workflow_dispatch) es el único anterior a todos los fixes.
### Defecto 1
- Job y etapa: smoke, etapa deploy (debía estar en post-deploy). Tenía `needs: build-push`, es decir, corría en paralelo con deploy.
- Problema que causa en el pipeline: smoke probaba la versión anterior de la Lambda o una a medio actualizar (race condition) y podía salir verde aunque la versión nueva no arrancara o aunque deploy fallara. Además arrastraba a e2e y load (ambos con `needs: smoke`). No recibía `EXPECTED_COMMIT`, así que no verificaba qué versión respondía.
- Link al commit: https://github.com/CaVassM/INF384-lab4-dev/commit/79363b14a2e22f013aeb92d81de8358c12bbf9fb
- Corrección (una o más: mover de etapa / dejar como informativo / eliminar / ajustar configuración / modificar tests): mover de etapa + ajustar configuración. `needs: deploy` y `EXPECTED_COMMIT: ${{ github.sha }}`.
- Evidencia (dato observado, con link al run o fragmento de la salida local):
  - ANTES, run 1 (sha 49ba49e): https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455
    - deploy: inicio 21:13:29Z (16:13:29 Lima), fin 21:13:52Z (16:13:52). Job: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455/job/123735897537
    - smoke: inicio 21:13:29Z (16:13:29), fin 21:13:58Z. Job: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455/job/123735896673
    - smoke empezó a la misma hora que deploy, 23 s antes de que deploy terminara. En este run el paso Smoke corrió a las 21:13:55Z, después del fin de deploy, solo porque el paso URL esperó 23 s; no estaba garantizado por el grafo de jobs.
    - El log de ese smoke no tiene `EXPECTED_COMMIT` en el `env` ni línea `commit:`:
      ```
      21:13:56.5943598Z salud: {"ok":true,"version":"1.0.0","commit":"49ba49ebee84f4c9f8b6943031595970311a3bb6"}
      21:13:56.6826623Z saldo: {"usuario":"ana","saldo":1000}
      ```
  - DESPUÉS, run 2 (headSha 79363b14a2e22f013aeb92d81de8358c12bbf9fb, el commit de este defecto): https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40957503675
    - deploy: 21:25:26Z a 21:25:42Z (16:25:26 a 16:25:42 Lima).
    - smoke: inicio 21:25:45Z (16:25:45), después de que deploy terminó. Job: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40957503675/job/123742021305
      ```
      21:25:51.9169814Z   EXPECTED_COMMIT: 79363b14a2e22f013aeb92d81de8358c12bbf9fb
      21:25:52.1325975Z salud: {"ok":true,"version":"1.0.0","commit":"79363b14a2e22f013aeb92d81de8358c12bbf9fb"}
      21:25:52.3196082Z commit: 79363b14a2e22f013aeb92d81de8358c12bbf9fb
      ```
  - DESPUÉS, run 6 (con los 5 fixes, headSha 6add4fa8aba641385adaf916e49f1812dd36f32b): https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960297837
    - deploy: 21:51:05Z a 21:51:22Z (16:51:05 a 16:51:22 Lima); smoke empezó a las 21:51:25Z (16:51:25). Job: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960297837/job/123754233170
      ```
      21:51:31.7497915Z   EXPECTED_COMMIT: 6add4fa8aba641385adaf916e49f1812dd36f32b
      21:51:32.8558740Z commit: 6add4fa8aba641385adaf916e49f1812dd36f32b
      ```
    - La línea `commit:` coincide con el headSha del run.
### Defecto 2
- Job y etapa: workflow completo (ci.yml), sin `concurrency` a nivel de workflow. Afecta a los jobs post-deploy (smoke, e2e, load), porque el `concurrency` del job deploy solo protege a ese job.
- Problema que causa en el pipeline: PR y main despliegan en la misma Lambda. Un run podía redesplegar mientras otro seguía ejecutando smoke, e2e o load, y esos jobs probaban el código de otro run en vez del suyo.
- Link al commit: https://github.com/CaVassM/INF384-lab4-dev/commit/19bf8d060d3957ced7d532dc2dd985293f332566
- Corrección (una o más: mover de etapa / dejar como informativo / eliminar / ajustar configuración / modificar tests): ajustar configuración. `concurrency: group: pipeline-${{ github.repository }}, cancel-in-progress: false` a nivel de workflow.
- Evidencia (dato observado, con link al run o fragmento de la salida local):
  - ANTES (runs sin concurrency de workflow que se solaparon):
    - Run 1 (https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455): el paso k6 del job load corrió de 21:14:09Z a 21:26:10Z (16:14:09 a 16:26:10 Lima).
    - Run 2 (https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40957503675) empezó a las 21:24:16Z (16:24:16) y su deploy corrió de 21:25:26Z a 21:25:42Z, es decir, redesplegó la Lambda mientras k6 del run 1 todavía estaba corriendo.
    - Run 2: load de 21:25:57Z a 21:38:07Z. Run 3 (https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40959149463) creado a las 21:36:00Z; su deploy corrió de 21:37:11Z a 21:37:28Z, también dentro del load del run 2. No verifiqué si estos solapes alteraron alguna métrica.
  - DESPUÉS (con el fix en main; estados consultados entre ~21:46Z y ~21:49Z (16:46 a 16:49 Lima), vía listado de runs de la API de GitHub; en ambas consultas el run 3 estaba in_progress y el run 6 pending):
    ```
    run 3  19bf8d0  in_progress   creado 21:36:00Z   https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40959149463
    run 6  6add4fa  pending       creado 21:44:26Z   https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960297837
    run 5  98c718e  cancelled     creado 21:42:30Z   https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960038388
    run 4  fae52a9  cancelled     creado 21:38:06Z   https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40959441718
    ```
    - El run 6 quedó `pending` mientras el run 3 estaba `in_progress`. Los runs 4 y 5 quedaron `cancelled` porque un run pendiente más nuevo reemplaza al pendiente anterior (con `cancel-in-progress: false` solo se cancela lo pendiente, no lo que está corriendo).
    - El run 3 terminó a las 21:49:50Z (16:49:50 Lima) y los jobs del run 6 se crearon a las 21:49:50Z: el run 6 esperó 5 min 24 s y no hubo solape.
### Defecto 3
- Job y etapa: sca, etapa pre-build.
- Problema que causa en el pipeline: Trivy corría con `--include-dev-deps`, por lo que escaneaba dependencias de desarrollo (Playwright, c8, esbuild) que no viajan en la imagen (el Dockerfile hace `npm prune --omit=dev`). Podía bloquear el despliegue por vulnerabilidades no alcanzables ni expuestas en producción. En el run 1 y en el run 2 de hoy el resultado fue 0 vulnerabilidades, así que el defecto no llegó a bloquear nada hoy; es un riesgo de falso bloqueo.
- Link al commit: https://github.com/CaVassM/INF384-lab4-dev/commit/fae52a9d1b3d6228c9ba6fe1d77142da01af32ea
- Corrección (una o más: mover de etapa / dejar como informativo / eliminar / ajustar configuración / modificar tests): ajustar configuración. Se quita `--include-dev-deps` del comando de Trivy.
- Evidencia (dato observado, con link al run o fragmento de la salida local):
  - Local (contenedor Linux de la sesión, Node v22.22.0, npm 10.9.4; ejecutado en el repo tras `npm ci`; cada número cuenta también la línea de la raíz del proyecto):
    ```
    $ npm ls --all --parseable | wc -l
    98
    $ npm ls --all --omit=dev --parseable | wc -l
    39
    $ grep -n prune Dockerfile
    8:RUN npm run build && npm prune --omit=dev
    ```
    La diferencia es de 59 entradas que solo aparecen en el árbol de desarrollo; con el flag, Trivy las incluía en su revisión aunque no llegan a la imagen.
  - ANTES, run 1 (job sca https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455/job/123735254109): el comando incluye el flag.
    ```
    21:12:16.7289635Z     --include-dev-deps \
    21:12:25.5834023Z │ package-lock.json │ npm  │        0        │
    ```
  - DESPUÉS, run 6 (job sca https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960297837/job/123753519860): el flag ya no está y Trivy lo informa en su log.
    ```
    21:50:02.2323422Z INFO Suppressing dependencies for development and testing. To display them, try the '--include-dev-deps' flag.
    21:50:02.2338664Z Report Summary
    ┌───────────────────┬──────┬─────────────────┐
    │      Target       │ Type │ Vulnerabilities │
    ├───────────────────┼──────┼─────────────────┤
    │ package-lock.json │ npm  │        0        │
    └───────────────────┴──────┴─────────────────┘
    ```
### Defecto 4
- Job y etapa: integration, etapa pre-build.
- Problema que causa en el pipeline: los tests de integración usaban una base fija (`DB_PATH: /tmp/wallet.db`) y dependían del estado y del orden (por ejemplo, el saldo 900 de ana dependía del test anterior). No eran aislados ni deterministas: si la base ya existía de una corrida previa, fallaban en cascada.
- Link al commit: https://github.com/CaVassM/INF384-lab4-dev/commit/98c718ec2b00de4d2bc369f9a82299cf95f1127a
- Corrección (una o más: mover de etapa / dejar como informativo / eliminar / ajustar configuración / modificar tests): modificar tests. `test/integration/transferir.test.js` fija `process.env.DB_PATH` a una base nueva creada con `fs.mkdtempSync` antes de cargar el handler. El commit no toca ci.yml, así que el `DB_PATH` fijo del job queda sin efecto.
- Evidencia (dato observado, con link al run o fragmento de la salida local):
  - ANTES: versión previa al fix (`git show 98c718e~1:test/integration/transferir.test.js`, guardada temporalmente con otro nombre), con `DB_PATH` apuntando al mismo archivo fijo, corrida dos veces seguidas con `node --test <archivo>`:
    ```
    === corrida 1 ===
    # tests 12
    # pass 12
    # fail 0
    === corrida 2 (misma base) ===
    # tests 12
    # pass 6
    # fail 6
    not ok 1 - ana transfiere 100 a beto          (expected: 900, actual: 800)
    not ok 2 - el saldo de ana refleja el debito
    not ok 3 - el saldo de beto refleja el credito
    not ok 4 - el historial de ana registra la transferencia
    not ok 6 - una transferencia rechazada no cambia saldos
    not ok 7 - diego transfiere todo su saldo a elena
    ```
    La segunda corrida falla porque la base ya contenía la transferencia de la primera. El archivo temporal y la base se borraron y no se commitearon.
  - DESPUÉS: test con el fix, dos corridas seguidas con `node --test test/integration/*.test.js`:
    ```
    # tests 12
    # pass 12
    # fail 0
    # tests 12
    # pass 12
    # fail 0
    ```
    Con Node 22 (el de este entorno), `npm run test:integration` (`node --test test/integration/`) no sirve porque Node 22 toma el directorio como ruta de módulo (`Error: Cannot find module '.../test/integration'`); por eso usé el glob. El CI usa Node 20, donde el script corre bien: job integration del run 6 en success (https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40960297837/job/123753519450).
### Defecto 5
- Job y etapa: load, etapa post-deploy.
- Problema que causa en el pipeline: load (k6) corría en cada pull request porque el trigger `pull_request` de ci.yml no estaba filtrado en el job. Cada push a un PR gastaba unos 12 minutos extra y mandaba tráfico de carga a la Lambda compartida, sin aportar información para decidir sobre el PR.
- Link al commit: https://github.com/CaVassM/INF384-lab4-dev/commit/6add4fa8aba641385adaf916e49f1812dd36f32b
- Corrección (una o más: mover de etapa / dejar como informativo / eliminar / ajustar configuración / modificar tests): ajustar configuración. `if: github.event_name != 'pull_request'` en el job load; sigue corriendo en cada run de main.
- Evidencia (dato observado, con link al run o fragmento de la salida local):
  - Run 1 (anterior a los fixes), job load: 21:14:00Z a 21:26:13Z (16:14:00 a 16:26:13 Lima) = 12:13 (min:seg); el paso k6 duró 12:01. Link: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40955729455/job/123736157445
  - Run 2, job load: 21:25:57Z a 21:38:07Z = 12:10. Link: https://github.com/CaVassM/INF384-lab4-dev/actions/runs/40957503675/job/123742130877
  - Antes del fix, `git show 79363b1~1:.github/workflows/ci.yml` muestra `on: pull_request:` en la línea 4 y el job `load:` en la línea 306 sin ninguna condición `if`.
  - Efecto de la corrección: en el run del PR de la Parte 2, load aparece como skipped [PENDIENTE: link al run del PR]

## Parte 2 · Implementación
- Link al run en verde en main:
- Link al pull request:
- Defecto de la aplicación introducido (archivo y descripción):
- Job que debería detenerlo:
- Link al run fallido:

## Parte 3 · Decisión bajo restricción
Link al run medido:

| Job | Duración (min:seg) |
|---|---|
| unit | |
| integration | |
| sast | |
| sca | |
| build-push | |
| deploy | |
| smoke | |
| e2e | |
| load | |
| **Total** | |

Resultado de load en ese run:
| Métrica | Valor |
|---|---|
| p90 | |
| p95 | |
| Máximo | |
| Tasa de error | |
| Requests por segundo | |

Conclusión sobre el comportamiento bajo carga:

SLO propuesto (percentil, valor, ventana) y justificación:

SLA propuesto y diferencia con el SLO:

Cambios para cumplir el presupuesto:
| Cambio | Job | Minutos recuperados |
|---|---|---|

Total resultante: [ ] min
Link al run en main con los cambios:

Riesgo aceptado (defecto de la aplicación concreto y efecto en la métrica DORA asignada):

Decisión sobre sast (se queda / se mueve a otra etapa o evento / informativo) y razón:

## Declaración de uso de IA
Herramientas usadas y para qué:
