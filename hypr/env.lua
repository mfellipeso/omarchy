-- Escala de aplicativos.
--
-- O Omarchy define GDK_SCALE no monitors.lua, que é por máquina e por isso
-- fica fora deste repo. O padrão dele é 2, e o Steam lê GDK_SCALE direto: com
-- 2 a interface dele sai gigante. Como isso é preferência, não hardware, mora
-- aqui — este arquivo é carregado depois do monitors.lua, e o último setenv
-- vence.
hl.env("GDK_SCALE", "1")
