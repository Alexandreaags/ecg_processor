library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_processor is
    port (
        clk_50mhz : in  std_logic;
        rst_n     : in  std_logic;
        hex5, hex4, hex2, hex1, hex0 : out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of ecg_processor is

    -- Componente da ROM (Deve ser o arquivo gerado pelo Python com "integer")
    component ecg_rom is
        port (
            clk  : in  std_logic; 
            addr : in  integer range 0 to 16383; 
            q    : out integer range 0 to 4095
        );
    end component;

    component ssd_decoder is
        port (in_val : in std_logic_vector(3 downto 0); out_seg: out std_logic_vector(6 downto 0));
    end component;

    -- DIVISOR DE CLOCK LENTO (Para permitir a divisão matemática)
    -- Vamos rodar a lógica inteira a ~250Hz (Lento o suficiente para dividir)
    -- 50MHz / 200.000 = 250Hz
    constant CLK_DIV_LIMIT : integer := 200_000; 
    signal clk_div_counter : integer range 0 to CLK_DIV_LIMIT := 0;
    signal clk_slow        : std_logic := '0'; 

    -- Sinais da Memória (Inteiros)
    signal rom_addr   : integer range 0 to 16383 := 0;
    signal sample_val : integer range 0 to 4095 := 0;

    -- Processamento
    constant THRESHOLD : integer := 3480; 
    signal samples_between_peaks : integer range 0 to 4095 := 0; 
    signal wait_release : boolean := false; 
    signal first_peak_detected : boolean := false;

    signal sample_counter_patient : integer range 0 to 188 := 0; 
    signal patient_total_count : integer range 1 to 80 := 1;

    -- Sinais de Display
    signal pat_tens, pat_units : integer range 0 to 9 := 0;
    signal bpm_val_int : integer range 0 to 999 := 0;
    signal bpm_hund, bpm_tens, bpm_unit : integer range 0 to 9 := 0;

begin

    -- Instância da ROM (Vetor Constante)
    rom_inst : ecg_rom
    port map (clk => clk_50mhz, addr => rom_addr, q => sample_val);
    
    -- 1. GERADOR DE CLOCK LENTO
    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if rst_n = '0' then
                clk_div_counter <= 0;
                clk_slow <= '0';
            else
                if clk_div_counter >= CLK_DIV_LIMIT then
                    clk_div_counter <= 0;
                    clk_slow <= not clk_slow; -- Inverte o clock
                else
                    clk_div_counter <= clk_div_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- 2. LÓGICA PRINCIPAL (Rodando no Clock Lento)
    process(clk_slow, rst_n)
    begin
        if rst_n = '0' then
            rom_addr <= 0;
            sample_counter_patient <= 0;
            patient_total_count <= 1;
            pat_tens <= 0; pat_units <= 1;
            samples_between_peaks <= 0;
            wait_release <= false;
            first_peak_detected <= false;
            bpm_val_int <= 0;
            
        elsif rising_edge(clk_slow) then
            
            -- A. Conta Distância
            if samples_between_peaks < 2000 then
                samples_between_peaks <= samples_between_peaks + 1;
            end if;

            -- B. Detecta Pico
            if sample_val > THRESHOLD then
                if not wait_release then
                    wait_release <= true; 
                    
                    if not first_peak_detected then
                        first_peak_detected <= true;
                        samples_between_peaks <= 0;
                    else
                        -- CÁLCULO REAL (Divisão Matemática)
                        -- Como estamos no clk_slow, o hardware tem milhares de ciclos de 50MHz 
                        -- para terminar essa conta antes do próximo pulso de clk_slow.
                        if samples_between_peaks > 5 then
                            bpm_val_int <= 7500 / samples_between_peaks;
                        end if;
                        
                        samples_between_peaks <= 0;
                    end if;
                end if;
            elsif sample_val < 2000 then 
                wait_release <= false;
            end if;

            -- C. Avança
            if sample_counter_patient = 187 then
                sample_counter_patient <= 0;
                first_peak_detected <= false; 
                samples_between_peaks <= 0;
                wait_release <= false;

                if patient_total_count = 80 then
                    patient_total_count <= 1;
                    pat_tens <= 0; pat_units <= 1;
                    rom_addr <= 0;
                else
                    patient_total_count <= patient_total_count + 1;
                    rom_addr <= rom_addr + 1;
                    
                    if pat_units = 9 then
                        pat_units <= 0; pat_tens <= pat_tens + 1;
                    else
                        pat_units <= pat_units + 1;
                    end if;
                end if;
            else
                sample_counter_patient <= sample_counter_patient + 1;
                rom_addr <= rom_addr + 1;
            end if;
            
        end if;
    end process;

    -- 3. SEPARAÇÃO DE DÍGITOS PARA DISPLAY (Combinacional)
    -- Isso roda fora do processo, usando lógica pura.
    process(bpm_val_int)
    begin
        if bpm_val_int > 999 then
            bpm_hund <= 9; bpm_tens <= 9; bpm_unit <= 9;
        else
            -- O sintetizador consegue lidar com essas divisões pequenas
            -- porque não estão dentro de um clock apertado
            bpm_hund <= bpm_val_int / 100;
            bpm_tens <= (bpm_val_int / 10) mod 10;
            bpm_unit <= bpm_val_int mod 10;
        end if;
    end process;

    -- Drivers
    disp_pat1: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(pat_tens, 4)), out_seg => hex5);
    disp_pat0: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(pat_units, 4)), out_seg => hex4);
    
    disp_bpm2: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_hund, 4)), out_seg => hex2);
    disp_bpm1: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_tens, 4)), out_seg => hex1);
    disp_bpm0: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_unit, 4)), out_seg => hex0);

end rtl;