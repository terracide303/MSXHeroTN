# Frontend gráfico "no-MSX" para MSXnano — Documento de diseño

> **Inherited from upstream — not part of this fork's plan.**
> This document belongs to [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) and
> is kept for reference only. It targets the Tang Console 60K and/or assumes the on-board
> BL616 companion, neither of which applies to MSXnano-MiSTle: this fork targets the Tang
> Nano 20K on a MiSTeryShield20k and has dropped the on-board BL616 path entirely. Nothing
> here describes work planned in this repository. See the [main README](../README.md) for the actual
> roadmap.


**Estado: FASE DE DISEÑO / investigación (2026-07-06).** Pregunta del usuario: sustituir el
menú MSX por un frontend gráfico bonito estilo EmuELEC/Batocera (con carátulas), NO limitado
al VDP MSX, que al elegir un juego lance el core MSX con el ROM/DSK. Investigado con panel
multi-agente (landscape multi-core, coste de construir el frontend, modelos de convivencia)
+ verificación en el repo. Ligado a [[msx_tang_nano_60k]].

## 1. Respuesta directa
SÍ es técnicamente posible, pero con una distinción crucial: NO es "instalar Batocera/EmuELEC". Es CONSTRUIR un frontend gráfico propio, estilo Game Bub (Eli Lipsitz), donde el MCU BL616 renderiza la UI bonita (carátulas, listas) y la envía a la FPGA, que la compone sobre el vídeo y la saca por el HDMI que ya generas. Al elegir un juego, el BL616 hace el handoff: carga el ROM/DSK en la megaram y reinicia el MSX (o reconfigura el bitstream). El frontend NO está limitado al VDP MSX porque no se dibuja con el VDP: lo dibuja el BL616 y lo pinta la lógica de vídeo de la FPGA (mismo camino HDMI, otra fuente de píxeles). Punto de partida REAL en tu repo: el canal SPI MCU↔FPGA ya existe y YA tiene un target OSD reservado (fpga/src/usb/mcu_spi_new.v:18-27: mcu_sys_strobe/mcu_hid_strobe/mcu_osd_strobe/mcu_sdc_strobe) y el BL616 ya es dueño de la SD (mcu_sdc_strobe + fpga/src/wondertang/sd_reader.sv). Es decir: el conducto de control y el acceso a las carátulas en SD ya están cableados; falta el renderizador gráfico (firmware) y un compositor de framebuffer (RTL). Esto va en el Console 60K, no en el TN20K.

## 2. Reality-check (por qué NO es "instalar Batocera")
Batocera, EmuELEC y MiSTer NO corren tal cual en un Tang, y la razón es de hardware, no de esfuerzo. Batocera/EmuELEC = Linux embebido + EmulationStation + RetroArch/libretro emulando por SOFTWARE sobre una CPU ARM (Rockchip/Amlogic); no reconfiguran ninguna FPGA. MiSTer sí reconfigura FPGA por juego, pero lo hace desde el ARM HPS del DE10-Nano (Cyclone V SoC: 2×Cortex-A9 @800MHz con Linux) que escribe el .rbf en la tela. Los tres dependen de un SoC con Linux para dibujar el menú gráfico. El Tang Nano 20K / Console 60K NO tiene SoC Linux: solo FPGA + el MCU BL616 (RISC-V, ~320-384MHz, ~480KB SRAM, SIN controlador HDMI propio — el vídeo SIEMPRE lo genera la FPGA). Por tanto EmulationStation es imposible aquí. Lo ÚNICO portable es el MODELO ABSTRACTO: un controlador renderiza el menú y hace handoff a la FPGA por juego. Además, el ecosistema de menús Tang que ya existe (FPGA-Companion, MiSTeryNano, TangCore, cores de nand2mario) hace ese handoff pero su OSD es SOLO TEXTO (buffer 32×28 caracteres enviado por UART/SPI), sin carátulas — no cumple tu deseo out-of-the-box. Un frontend gráfico con cover art en FPGA pelada NO existe reutilizable; hay que construirlo. Lo que SÍ es replicable y verificado: la arquitectura de Game Bub (MCU dibuja UI con Slint → framebuffer RGB15+alpha por QSPI ~20MB/s → la FPGA compone UI sobre vídeo del emulador y saca a pantalla → el MCU reconfigura el bitstream por consola). Es casi 1:1 con tu BL616+FPGA. Reutilizas: la ARQUITECTURA de referencia (no el código), tu canal SPI con target OSD ya existente, el acceso SD del BL616, y todo el camino HDMI (tn_vdp_v3_v9958/src/hdmi/*.sv + vdp_vga.vhd). Construyes: el renderizador de UI en el BL616 y un compositor/escalador en RTL. OJO de licencia: vdp_vga.vhd (Ohnaka) prohíbe uso comercial sin permiso escrito — condiciona qué se puede redistribuir.

## 3. Hook verificado en el repo (el punto de partida real)
El canal SPI BL616↔FPGA YA reserva un **target OSD**: `fpga/src/usb/mcu_spi_new.v:18-27` define
`mcu_{sys,hid,osd,sdc}_strobe`, direccionados por el primer byte de cada transacción
(`spi_target==2` → OSD, líneas 74-77). PERO está **stubbeado**: `fpga/src/usb/fpga_companion.v:85`
ata `.mcu_osd_din(8'b0)` y no hay ningún renderer que consuma `mcu_osd_strobe` (herencia de
MiSTeryNano/FPGA-Companion que este fork no activó porque usa el menú MSX). El BL616 además ya
es dueño de la SD (`mcu_sdc_strobe` + `fpga/src/wondertang/sd_reader.sv`). → El conducto de
control y el acceso a las carátulas en SD YA están cableados; falta el **renderer gráfico**
(firmware BL616) y un **compositor de framebuffer** (RTL).

Referencia de arquitectura probada y casi 1:1 con tu BL616+FPGA: **Game Bub** (Eli Lipsitz,
open-source): un MCU (ESP32-S3) renderiza la UI con Slint y envía el framebuffer RGB15+alpha
por QSPI (~20MB/s); la FPGA lo compone sobre el vídeo del emulador y saca a pantalla; el MCU
carga el bitstream por consola. Se copia la ARQUITECTURA, no el código.

## 4. Arquitecturas evaluadas
### A) Companion-OSD enriquecido del BL616 (carátulas simples sobre el OSD existente)
- **Convivencia**: companion-osd · **Esfuerzo**: medio · **¿Cabe en TN20K?**: Sí
- **Cómo**: Extender el target OSD que YA existe en el canal SPI (mcu_spi_new.v: mcu_osd_strobe) de texto a un overlay bitmap pequeño: el BL616 lee la carátula pre-escalada/pre-decodificada de la SD (ya es dueño de la SD vía mcu_sdc_strobe + sd_reader.sv), la manda por SPI y la FPGA la pinta en una ventana del OSD sobre el vídeo del menú/core. No es un framebuffer completo: es un overlay tipo MiSTer (tile/ventana) con una miniatura de carátula + texto bonito.
- **Carátulas**: Carátula pequeña pre-escalada (p.ej. 128x128 o 160x200) decodificada en el BL616 y enviada como bitmap a una ventana OSD; una imagen a la vez (la del juego seleccionado), no un grid 60fps. Actualización a ritmo de menú, no de frame.
- **Reutiliza / construye**: MUCHO: canal SPI + target OSD (mcu_spi_new.v:18-27), acceso SD del BL616 (sd_reader.sv), camino HDMI completo. Se construye: firmware de decodificación+envío en BL616 y ampliar el bloque OSD del RTL de texto a bitmap.
- **Pros**: El menor salto desde lo que ya tienes; reusa el conducto existente; probablemente cabe hasta en TN20K (overlay pequeño, no segundo sistema de vídeo). Handoff ya resuelto (el BL616 ya lanza juegos). Da el 'wow' de carátula sin reescribir el pipeline.
- **Contras**: No es un frontend 'Batocera' de pantalla completa: es un menú con una carátula, no un grid animado de portadas con scroll fluido. El menú de fondo sigue siendo el actual (MSX o un fondo simple), no una UI totalmente libre. Estético limitado por el tamaño del overlay.
### B) Blitter + framebuffer en DDR3 comandado por el BL616 (el 'Game Bub' propio)
- **Convivencia**: companion-osd · **Esfuerzo**: alto · **¿Cabe en TN20K?**: No (Console 60K)
- **Cómo**: En el Console 60K, un framebuffer completo en DDR3 (512MB da de sobra) que posee la FPGA; el BL616 renderiza la UI (Slint/LVGL) y envía SOLO tiles/regiones sucias por SPI/QSPI (partial rendering, como Game Bub), o comanda un pequeño blitter en RTL (copia rects, escala, alpha-blend carátulas). Un compositor lee el framebuffer y lo saca por el HDMI existente; en modo juego, compone la UI (semitransparente/overlay) sobre el vídeo del core o la sustituye. Al elegir juego: handoff a megaram + reset del MSX.
- **Carátulas**: Grid completo de carátulas con scroll: el BL616 decodifica JPG/PNG pre-escalados de la SD y los blitea al framebuffer DDR3; el blitter RTL hace el escalado/alpha. Esto SÍ es un frontend bonito de pantalla completa tipo EmulationStation.
- **Reutiliza / construye**: MEDIO: reusa el canal SPI (ampliándolo a QSPI para ancho de banda), acceso SD, camino HDMI (hdmi/*.sv), y el controlador DDR3 del port 60K. Se construye: compositor+blitter RTL (net-new), firmware UI del BL616 (net-new), protocolo de framebuffer.
- **Pros**: Es EXACTAMENTE lo que el usuario pide y hay referencia probada (Game Bub open-source, arquitectura casi idéntica: MCU+FPGA, framebuffer del lado FPGA, partial render del MCU). Aprovecha la DDR3 del 60K (el TN20K no la tiene). Frontend totalmente libre del VDP MSX, animaciones, transiciones. Escala a otros cores del futuro.
- **Contras**: Net-new RTL (blitter/compositor/escalador) + net-new firmware BL616 con GUI framework — el mayor bloque de trabajo original. 480KB SRAM del BL616 obliga a partial rendering + framebuffer del lado FPGA (no cabe frame completo en el MCU). NO cabe en TN20K (89% CLS). Requiere el port 60K terminado primero.
### C) Soft-SoC (LiteX/VexRiscv) que dibuja el frontend dentro de la FPGA
- **Convivencia**: hibrido · **Esfuerzo**: muy alto · **¿Cabe en TN20K?**: No (Console 60K)
- **Cómo**: Instanciar un soft-CPU RISC-V (LiteX + VexRiscv) DENTRO de la FPGA con su propio framebuffer en DDR3 y un core de vídeo; ese SoC corre el frontend (C/Rust o incluso un Linux mínimo en LiteX) y, al elegir juego, reconfigura/entrega el control al core MSX. En vez de usar el BL616 externo, el 'cerebro gráfico' es lógica de la propia FPGA.
- **Carátulas**: Framebuffer propio del soft-SoC en DDR3 con librería gráfica corriendo en el VexRiscv; carátulas decodificadas por el soft-CPU. Potencia equivalente a B pero todo dentro de la FPGA.
- **Reutiliza / construye**: BAJO en lo específico del proyecto: reusa el camino HDMI y DDR3, pero introduce un stack nuevo (LiteX) que hay que integrar con tu core MSX y tu toolchain Gowin. El BL616 quedaría solo para USB/teclado.
- **Pros**: Frontend muy potente e independiente del BL616 (no dependes de la SRAM/CPU del MCU); un soft-CPU con Linux/LiteX puede montar SD, decodificar imágenes, red, etc. Ecosistema LiteX maduro para Xilinx/Lattice.
- **Contras**: Coste de lógica ALTO (soft-CPU + MMU + framebuffer + periféricos compiten con el core MSX por LUTs del GW5AT-60); soporte LiteX en Gowin GW5A es inmaduro/no oficial (riesgo real de toolchain). Duplica un 'cerebro' que ya tienes en el BL616 — desperdicia el MCU. Peor relación esfuerzo/beneficio que B para el mismo resultado visual. Solo tiene sentido si se descarta usar el BL616 como renderizador.
### D) Reconfiguración total estilo MiSTer (bitstream 'monitor' separado + bitstreams por core)
- **Convivencia**: reconfig-total · **Esfuerzo**: alto · **¿Cabe en TN20K?**: Sí
- **Cómo**: Un bitstream 'menú/monitor' independiente (que puede incluir el frontend gráfico de B o C) corre solo; al elegir juego, el BL616 hace streaming del bitstream del core MSX (o de otro core) a la FPGA y arranca. No conviven dos sistemas de vídeo a la vez: se SUSTITUYEN por reconfiguración (nand2mario mide ~2s optimizado). Complementa B: define CÓMO se separa el frontend del core en el tiempo.
- **Carátulas**: La del bitstream de menú (por tanto, tan bonita como B o C, ya que el menú es su propio bitstream con framebuffer dedicado y sin compartir lógica con el core MSX).
- **Reutiliza / construye**: Reusa el mecanismo de carga de bitstream del BL616 (ya carga/gestiona la FPGA para teclado; TangCore/nand2mario demuestran /cores en SD). Se construye: el flujo de multi-bitstream, y el bitstream de menú (que es B o C).
- **Pros**: El frontend NO compite por lógica con el core MSX (viven en bitstreams distintos) — resuelve el 89% CLS del TN20K para la parte de menú. Modelo probado en Tang (TangCore, nand2mario ~2s de reconfig). Escala a multi-core (NES/SNES/MSX...). Casa con tu restricción conocida: la SDRAM/megaram es volátil y se pierde en cualquier reconfiguración de todos modos.
- **Contras**: El handoff pierde el estado (reconfig = reset total; coherente con tu megaram volátil, pero el retorno menú→juego→menú recarga flash cada vez). Complejidad de gestionar N bitstreams y el arranque. Sigues necesitando construir el bitstream de menú bonito (B o C) — D es el 'cómo se orquesta', no ahorra el trabajo del frontend gráfico. ~2s de conmutación visible.

## 5. Recomendación
Ruta escalonada, target Tang Console 60K (GW5AT-60) para todo lo gráfico nuevo — el TN20K al 89% CLS solo aguanta la Fase 1. FASE 1 (ya, bajo riesgo, incluso en TN20K): Arquitectura A. Ampliar el target OSD que YA existe en mcu_spi_new.v de texto a un overlay bitmap y que el BL616 lea una carátula pre-escalada de la SD (ya es dueño de la SD). Consigues 'menú con carátula' reutilizando el 90% del conducto existente, sin tocar el pipeline de vídeo ni depender del port 60K. Es la validación barata de que el modelo MCU-dibuja / FPGA-compone funciona en tu hardware. FASE 2 (cuando llegue y esté portado el Console 60K): Arquitectura B, el 'Game Bub propio'. Framebuffer completo en DDR3 propiedad de la FPGA + compositor/blitter RTL + firmware UI en el BL616 (Slint o LVGL, partial rendering porque los 480KB de SRAM no dan para frame completo, carátulas JPG/PNG pre-escaladas en SD). Copia la arquitectura de Game Bub (open-source, casi 1:1 con tu BL616+FPGA), NO su código. Esto es el frontend bonito de pantalla completa tipo Batocera que quieres. FASE 3 (organizativa, si vas a multi-core): envolver B en el modelo D (bitstream de menú separado + streaming de bitstream por core), que además esquiva el problema de compartir lógica con el core MSX y encaja con tu megaram volátil (la reconfig resetea de todos modos). DESCARTAR C (soft-SoC LiteX) salvo que decidas no usar el BL616 como renderizador: para el mismo resultado visual cuesta mucho más lógica y el soporte LiteX en Gowin GW5A es inmaduro; además duplica un cerebro que ya tienes. Regla de honestidad para comunicar al usuario: no prometas 'correr Batocera'; promete 'un frontend gráfico companion estilo Game Bub, con carátulas, construido para MSXnano, en el Console 60K'.

## 6. Preguntas abiertas
- Ancho de banda del enlace BL616→FPGA: el canal actual es SPI byte a byte (mcu_spi_new.v). ¿A qué reloj corre hoy y hay pines libres para pasar a QSPI 4-bit como Game Bub (~20MB/s) en el Console 60K? Un grid de carátulas necesita más que el UART/SPI de texto actual.
- ¿El controlador DDR3 del port 60K expondrá un puerto de escritura/lectura libre para un framebuffer del frontend, o toda la DDR3 estará ocupada por el core MSX (VRAM/megaram)? Determina si B es viable sin robar ancho de banda al MSX.
- Presupuesto de SRAM del BL616 (480KB) con USB-host de teclado YA activo + GUI framework + decodificador JPG/PNG + buffers de tiles sucios: ¿cabe Slint/LVGL a la vez que el firmware de teclado actual, o hace falta un segundo MCU / mover el teclado?
- Handoff y estado: con megaram volátil, el ciclo menú→juego→menú recarga flash y resetea. ¿Se acepta el ~2s (modelo D) y la pérdida de estado, o se quiere 'suspend/resume' del juego (que exigiría snapshot de SDRAM a SD, mucho más trabajo)?
- Licencia: vdp_vga.vhd (Ohnaka) prohíbe uso comercial sin permiso escrito, y el firmware PicoVerse es CC-BY-NC. Si el MSXnano se vende, ¿qué piezas del camino de vídeo/frontend son redistribuibles comercialmente y cuáles hay que reimplementar clean-room?
- ¿El frontend debe soportar solo MSX o es la semilla de un multi-core (SG-1000/Coleco ya existen en v1.8)? Si es multi-core, el modelo D (bitstream de menú separado) gana peso desde el principio y cambia el diseño de la Fase 2.
- Origen de las carátulas: ¿se generan/empaquetan offline en el Pack Builder (PySide6) pre-escaladas al tamaño exacto del overlay/grid, o el BL616 escala en runtime? Pre-escalar en el Pack Builder descarga muchísimo al MCU.

## 7. Ficheros clave del repo
- `fpga/src/usb/mcu_spi_new.v` (canal SPI BL616, target OSD reservado), `fpga/src/usb/fpga_companion.v` (OSD stubbeado, din=0).
- `fpga/src/wondertang/sd_reader.sv` (SD, ya del BL616).
- `fpga/tn_vdp_v3_v9958/src/hdmi/*.sv` + `vdp_vga.vhd` (camino HDMI; ⚠️ vdp_vga.vhd de Ohnaka = NO comercial sin permiso).
- Menú MSX actual: `fpga/src/msxnano_menu/` (se sustituiría/coexistiría).
