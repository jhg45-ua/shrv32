# ==============================================================================
# Proyecto: SHRV32 (Space-Hardened RISC-V 32)
# Script:   create_project.tcl — Crea el proyecto Vivado en build/vivado/
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/../.."]
set proj_dir   "$repo_root/build/vivado"
set proj_name  "shrv32"
set part_name  "xc7a100tcsg324-1"

file mkdir $proj_dir

# Crear proyecto limpio sin copiar los fuentes a build/
create_project -force $proj_name $proj_dir -part $part_name

# Añadir módulos RTL sintetizables por subcarpetas
set rtl_files [concat \
    [glob -nocomplain "$repo_root/rtl/core/*.v"] \
    [glob -nocomplain "$repo_root/rtl/mem/*.v"] \
    [glob -nocomplain "$repo_root/rtl/periph/*.v"] \
    [glob -nocomplain "$repo_root/rtl/top/*.v"] \
]

# Si aún no hay núcleo endurecido en rtl/core/, usar el submódulo upstream de referencia
if {[llength [glob -nocomplain "$repo_root/rtl/core/*.v"]] == 0} {
    lappend rtl_files "$repo_root/external/picorv32/picorv32.v"
}
if {![file exists "$repo_root/rtl/periph/simpleuart.v"]} {
    lappend rtl_files "$repo_root/external/picorv32/picosoc/simpleuart.v"
}

if {[llength $rtl_files] > 0} {
    add_files -fileset sources_1 -norecurse $rtl_files
}

# Añadir firmware.hex si ya está compilado (para $readmemh en síntesis/sim)
set hex_file "$repo_root/build/firmware.hex"
if {[file exists $hex_file]} {
    add_files -fileset sources_1 -norecurse $hex_file
}

# Definir módulo raíz (Top-Level)
set_property top System [current_fileset]

# Añadir archivo de restricciones de la Nexys A7 100T
set xdc_file "$script_dir/Nexys-A7-100T-Master.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}

# Añadir testbenches al conjunto de simulación
set tb_files [glob -nocomplain "$repo_root/tb/*.v"]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: Proyecto Vivado generado en $proj_dir/$proj_name.xpr"
