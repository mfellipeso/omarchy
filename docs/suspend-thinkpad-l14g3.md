# Suspensão no ThinkPad L14 Gen3 AMD

Correção para o notebook que acorda sozinho logo depois de suspender quando está
na tomada.

## Sintoma

- `systemctl suspend` ou fechar a tampa: a máquina entra em suspensão e volta
  em ~1–2 s.
- Só acontece com o carregador conectado; na bateria suspende normalmente.
- Começou com o Omarchy 4.5 (kernel `linux-omarchy` 7.2.x). Em versões antigas
  (kernel 6.x) não acontecia.

```
PM: suspend entry (s2idle)
PM: suspend exit            ← 1 s depois
```

## Hardware

| Item      | Valor                                      |
|-----------|--------------------------------------------|
| Modelo    | ThinkPad L14 Gen3 AMD (`21C6`)             |
| CPU       | Ryzen 5 PRO 5675U (Barcelo, família Cezanne) |
| BIOS      | R1YET62W (1.39), 2026-05-26                |
| Sleep     | `s2idle` (sem S3)                          |

## Causa

Com `echo 1 | sudo tee /sys/power/pm_debug_messages`, o log do kernel mostra:

```
PM: Triggering wakeup from IRQ 9      ← evento do EC (bateria/carregador)
PM: Triggering wakeup from IRQ 1      ← i8042 (teclado interno), sem tecla nenhuma
ACPI: PM: Wakeup after ACPI Notify sync
PM: suspend exit
```

- Na tomada, o EC manda eventos de bateria/carregador com frequência (IRQ 9,
  GPE 0x03). Sozinho isso não acorda: o kernel trata o evento e volta a dormir.
- Junto com o evento do EC, os SoCs Renoir/Cezanne/Barcelo geram uma **IRQ 1
  espúria** do controlador de teclado. Como o teclado interno (`serio0`) é
  fonte de wakeup, a máquina acorda.
- O kernel tem um workaround para isso no `amd_pmc`: para CPUs Cezanne ele
  liga `disable_8042_wakeup` e desativa o wakeup do `serio0` na suspensão.
  Quando ativo, o boot loga `Disabling IRQ1 wakeup source to avoid platform
  firmware bug`.

### A regressão

O commit [`1a9452c428a6`](https://github.com/torvalds/linux/commit/1a9452c428a6)
("Add Thinkpad L14 Gen3 to quirk_s2idle_bug", março/2026, [bug 221273](https://bugzilla.kernel.org/show_bug.cgi?id=221273))
adicionou o L14 Gen3 à `fwbug_list` com `quirk_s2idle_bug` para corrigir outro
problema (atraso de 10 s no resume). Mas `amd_pmc_quirks_init()` termina com:

```c
if (dev->cpu_id == AMD_CPU_ID_CZN)
        dev->disable_8042_wakeup = true;
...
dev->disable_8042_wakeup = dev->quirks->spurious_8042;   /* sobrescreve */
```

Como `quirk_s2idle_bug` tem `spurious_8042 = false`, o match DMI **desliga** o
workaround da IRQ 1 que o L14 Gen3 recebia por ser Cezanne. O commit está no
7.0+ e também foi para o **6.18 LTS** (6.18.57 tem o mesmo código), então
trocar para `linux-lts` não resolve.

A correção certa no kernel seria usar `quirk_s2idle_spurious_8042` na entrada
do L14 Gen3, como já é no L14 Gen2 (`20X5`).

### O limite de carga não é a causa

O limite de 75–80% (gravado no EC pelo Lenovo Vantage, persiste entre sistemas)
deixa o EC mais ativo na tomada, mas a causa é a IRQ 1. Com a correção abaixo a
máquina suspende normalmente com o limite ativo.

## Correção

Desativar o teclado interno como fonte de wakeup, que é o que o kernel faria
sem a regressão:

```
# /etc/udev/rules.d/90-l14g3-no-kbd-wake.rules
ACTION=="add", SUBSYSTEM=="serio", KERNEL=="serio0", ATTR{power/wakeup}="disabled"
```

Aplicar sem reiniciar:

```sh
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=serio
cat /sys/bus/serio/devices/serio0/power/wakeup   # → disabled
```

Efeito colateral: tecla do teclado interno não acorda mais a máquina. Tampa,
botão de energia e teclado USB continuam acordando.

### Teste temporário (até reiniciar)

```sh
echo disabled | sudo tee /sys/bus/serio/devices/serio0/power/wakeup
```

Desfazer: `echo enabled | sudo tee /sys/bus/serio/devices/serio0/power/wakeup`.

## Verificação

```sh
echo 1 | sudo tee /sys/power/pm_debug_messages        # volta a 0 no reboot
systemctl suspend                                     # com carregador
journalctl -k -b | grep -E 'PM: suspend (entry|exit)|Triggering wakeup' | tail
```

Esperado: vários `IRQ 9` sem sair da suspensão, nenhum `IRQ 1`, e o intervalo
entre `entry` e `exit` igual ao tempo que ficou suspenso.

## Alternativas descartadas

- `acpi.ec_no_wakeup=1`: também funciona, mas bloqueia todo wakeup via EC — nos
  ThinkPads isso inclui abrir a tampa e teclas Fn. Mais amplo que o necessário.
- `linux-lts`: 6.18 LTS tem o mesmo commit.
- Remover o limite de carga: reduz os eventos do EC, mas não elimina a causa.

## Quando remover

Quando o kernel corrigir a entrada do L14 Gen3. Para checar, apague a regra,
reinicie e procure no boot:

```sh
journalctl -k -b | grep 'Disabling IRQ1 wakeup source'
```

Se a linha aparecer, o kernel voltou a aplicar o workaround e a regra é
desnecessária.
