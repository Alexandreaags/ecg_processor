library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_processor is
    port (
        clk_50mhz : in  std_logic;
        rst_n     : in  std_logic;
        -- Adicionei hex3 na lista de saídas
        hex5, hex4, hex3, hex2, hex1, hex0 : out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of ecg_processor is

    -- Componentes existentes
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

    -- === NOVO COMPONENTE FUZZY ===
    component Fuzzy_Heart_Diag is
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            bpm_in   : in  std_logic_vector(7 downto 0);
            diag_out : out std_logic_vector(1 downto 0)
        );
    end component;

    -- Sinais de Clock
    constant CLK_DIV_LIMIT : integer := 200_000; 
    signal clk_div_counter : integer range 0 to CLK_DIV_LIMIT := 0;
    signal clk_slow        : std_logic := '0'; 

    -- Sinais da ROM e Processamento
    signal rom_addr              : integer range 0 to 16383 := 0;
    signal sample_val            : integer range 0 to 4095 := 0;
    constant THRESHOLD           : integer := 3480; 
    signal samples_between_peaks : integer range 0 to 4095 := 0; 
    signal wait_release          : boolean := false; 
    signal first_peak_detected   : boolean := false;
    signal sample_counter_patient: integer range 0 to 188 := 0; 
    signal patient_total_count   : integer range 1 to 80 := 1;

    -- Sinais de Display Numérico
    signal pat_tens, pat_units : integer range 0 to 9 := 0;
    signal bpm_val_int         : integer range 0 to 999 := 0;
    signal bpm_hund, bpm_tens, bpm_unit : integer range 0 to 9 := 0;

    -- === SINAIS PARA LÓGICA FUZZY ===
    signal fuzzy_bpm_input : std_logic_vector(7 downto 0);
    signal diag_result     : std_logic_vector(1 downto 0);
    signal reset_high      : std_logic; -- O módulo fuzzy usa reset ativo em '1'

begin

    -- Instância da ROM
    rom_inst : ecg_rom
    port map (clk => clk_50mhz, addr => rom_addr, q => sample_val);

    -- === INTEGRAÇÃO FUZZY ===
    
    -- 1. Inversão do Reset (seu sistema é rst_n, o fuzzy interno usa reset positivo por padrão)
    reset_high <= not rst_n;

    -- 2. Preparação do dado para o Fuzzy:
    -- O Fuzzy aceita max 255 (8 bits). Se o BPM for > 255, travamos em 255.
    process(bpm_val_int)
    begin
        if bpm_val_int > 255 then
            fuzzy_bpm_input <= "11111111"; -- 255
        else
            fuzzy_bpm_input <= std_logic_vector(to_unsigned(bpm_val_int, 8));
        end if;
    end process;

    -- 3. Instância Fuzzy
    -- Usamos clk_50mhz. O módulo vai processar sempre que 'bpm_val_int' mudar.
    fuzzy_inst : Fuzzy_Heart_Diag
    port map (
        clk      => clk_50mhz,
        reset    => reset_high,
        bpm_in   => fuzzy_bpm_input,
        diag_out => diag_result
    );

    -- 4. Decodificador para HEX3 (Diagnóstico)
    -- "00": Indefinido (-), "01": Baixo (L), "10": Normal (n), "11": Alto (H)
    process(diag_result)
    begin
        case diag_result is
            when "01" => hex3 <= "1000111"; -- L (Low) - 0 acende: gfedcba -> 1000111 (L)
            when "10" => hex3 <= "0101011"; -- n (Normal) 
            when "11" => hex3 <= "0001001"; -- H (High)
            when others => hex3 <= "0111111"; -- Traço (-)
        end case;
    end process;

    -- ==========================================
    -- LÓGICA EXISTENTE (Mantida igual)
    -- ==========================================

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
                    clk_slow <= not clk_slow;
                else
                    clk_div_counter <= clk_div_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- 2. LÓGICA PRINCIPAL (ECG)
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
                        -- CÁLCULO DE BPM
                        if samples_between_peaks > 5 then
                            bpm_val_int <= 7500 / samples_between_peaks;
                        end if;
                        
                        samples_between_peaks <= 0;
                    end if;
                end if;
            elsif sample_val < 2000 then 
                wait_release <= false;
            end if;

            -- C. Controle de Pacientes (Loop)
            if sample_counter_patient = 187 then
                sample_counter_patient <= 0;
                first_peak_detected <= false; 
                samples_between_peaks <= 0;
                wait_release <= false;
                
                -- IMPORTANTE: Resetar BPM entre pacientes para o Fuzzy não segurar o valor anterior
                bpm_val_int <= 0; 

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

    -- 3. SEPARAÇÃO DE DÍGITOS
    process(bpm_val_int)
    begin
        if bpm_val_int > 999 then
            bpm_hund <= 9; bpm_tens <= 9; bpm_unit <= 9;
        else
            bpm_hund <= bpm_val_int / 100;
            bpm_tens <= (bpm_val_int / 10) mod 10;
            bpm_unit <= bpm_val_int mod 10;
        end if;
    end process;

    -- Drivers Display
    disp_pat1: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(pat_tens, 4)), out_seg => hex5);
    disp_pat0: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(pat_units, 4)), out_seg => hex4);
    
    disp_bpm2: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_hund, 4)), out_seg => hex2);
    disp_bpm1: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_tens, 4)), out_seg => hex1);
    disp_bpm0: component ssd_decoder port map (in_val => std_logic_vector(to_unsigned(bpm_unit, 4)), out_seg => hex0);

end rtl;