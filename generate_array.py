import pandas as pd
import numpy as np

# 1. Carregar o CSV
try:
    df = pd.read_csv('ptbdb_normal.csv', header=None)
except FileNotFoundError:
    print("Erro: Coloque o arquivo ptbdb_normal.csv na pasta!")
    exit()

# 2. Pegar 80 pacientes (80 * 188 = 15040 amostras)
data = df.iloc[:80].values.flatten()

# 3. Escalar para 12 bits (0 a 4095)
# Nota: Convertemos para INTEIRO puro, pois vamos usar num array de inteiros
scaled_data = (data * 4095).astype(int)

# 4. Gerar o código VHDL (Entidade completa)
vhdl_code = """library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_rom is
    port (
        clk  : in  std_logic;
        addr : in  integer range 0 to 16383; -- Endereço agora é Inteiro para facilitar
        q    : out integer range 0 to 4095   -- Saída Inteira
    );
end entity;

architecture rtl of ecg_rom is
    -- Definição do Array Gigante
    type memory_t is array(0 to 16383) of integer range 0 to 4095;
    
    constant ROM_DATA : memory_t := (
"""

# Adiciona os dados
for i in range(16384):
    val = scaled_data[i] if i < len(scaled_data) else 0
    vhdl_code += f"        {i} => {val},\n"

# Finaliza o arquivo
vhdl_code += """        others => 0
    );
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- Leitura direta do vetor
            q <= ROM_DATA(addr);
        end if;
    end process;
end rtl;
"""

# 5. Salvar no arquivo
with open('ecg_rom.vhd', 'w') as f:
    f.write(vhdl_code)

print("Sucesso! O arquivo 'ecg_rom.vhd' foi gerado com o vetor embutido.")