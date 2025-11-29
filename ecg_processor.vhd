library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_processor is
    port (
        clk_50mhz : in  std_logic;
        rst_n     : in  std_logic;
        sw_mode   : in  std_logic; 
        y         : out std_logic; 
        led_mode  : out std_logic; 
        hex5, hex4, hex3, hex2, hex1, hex0 : out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of ecg_processor is

    component ecg_rom is
        port (clk : in std_logic; addr : in integer range 0 to 16383; q : out integer range 0 to 4095);
    end component;

    component ssd_decoder is
        port (in_val : in std_logic_vector(3 downto 0); out_seg: out std_logic_vector(6 downto 0));
    end component;

    component Multi_Fuzzy_Diag is
        Port (
            clk : in std_logic; reset : in std_logic; bpm_in : in std_logic_vector(7 downto 0);
            diag_child, diag_adult, diag_elder : out std_logic_vector(1 downto 0)
        );
    end component;

    -- DEFINIÇÃO DOS ESTADOS E SINAIS "NEXT" (PARA SEPARAÇÃO)

    -- FSM 1: Máquina de Estados Principal (Detecção de Pico)
    type state_type is (ST_IDLE, ST_WAIT_RELEASE, ST_MEASURING);
    signal current_state, next_state : state_type; -- Separado em Atual e Próximo

    -- FSM 2: Máquina de Estados para Controle de Ciclos (6 Leitura / 2 Ocio)
    type burst_state_type is (ST_IDLE_2, ST_READING_6);
    signal burst_state, next_burst_state : burst_state_type; -- Separado em Atual e Próximo
    
    -- Sinais auxiliares da FSM 2
    signal burst_cnt       : integer range 0 to 7 := 0;
    signal next_burst_cnt  : integer range 0 to 7;
    signal enable_read_node: std_logic; -- Sinal combinacional intermediário

    -- SINAIS DE DADOS
    signal stored_id_tens : integer range 0 to 9 := 0;
    signal stored_id_unit : integer range 0 to 9 := 0; 
    signal stored_bpm     : integer range 0 to 999 := 0;
    
    signal active_id_tens : integer range 0 to 9 := 0;
    signal active_id_unit : integer range 0 to 9 := 1;
    signal active_bpm     : integer range 0 to 999 := 0;
    signal pat_global_cnt : integer range 1 to 80 := 1;

    signal rom_addr       : integer range 0 to 16383 := 0;
    signal sample_data    : integer range 0 to 4095 := 0;
    signal sample_cnt     : integer range 0 to 188 := 0; 
    signal peak_timer     : integer range 0 to 2000 := 0;
    
    signal tick_enable    : std_logic; 
    signal div_cnt        : integer range 0 to 600000 := 0; 
    signal show_diag_mode : std_logic;

    signal fzy_in  : std_logic_vector(7 downto 0);
    signal d_child, d_adult, d_elder : std_logic_vector(1 downto 0);
    signal s_idt, s_idu, s_bph, s_bpt, s_bpu : std_logic_vector(6 downto 0);

    function get_char(code : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        case code is
            when "01" => return "1000111"; 
            when "10" => return "0101011"; 
            when "11" => return "0001001"; 
            when others => return "0111111";
        end case;
    end function;

begin

    rom_i : ecg_rom port map (clk_50mhz, rom_addr, sample_data);
    
    y <= enable_read_node; 
    led_mode <= sw_mode;

    fzy_in <= std_logic_vector(to_unsigned(stored_bpm, 8)) when stored_bpm < 255 else "11111111";
    
    fzy_i : Multi_Fuzzy_Diag port map (
        clk => clk_50mhz, reset => not rst_n, bpm_in => fzy_in,
        diag_child => d_child, diag_adult => d_adult, diag_elder => d_elder
    );

    -- Decoders SSD
    u0: ssd_decoder port map (std_logic_vector(to_unsigned(stored_id_tens, 4)), s_idt);
    u1: ssd_decoder port map (std_logic_vector(to_unsigned(stored_id_unit, 4)), s_idu);
    u2: ssd_decoder port map (std_logic_vector(to_unsigned(stored_bpm/100, 4)), s_bph);
    u3: ssd_decoder port map (std_logic_vector(to_unsigned((stored_bpm/10) mod 10, 4)), s_bpt);
    u4: ssd_decoder port map (std_logic_vector(to_unsigned(stored_bpm mod 10, 4)), s_bpu);

    show_diag_mode <= '1' when sample_cnt > 94 else '0';

    process(show_diag_mode, s_idt, s_idu, s_bph, s_bpt, s_bpu, d_child, d_adult, d_elder)
    begin
        if show_diag_mode = '0' then
            hex5 <= s_idt; hex4 <= s_idu; 
            hex3 <= "1111111";              
            hex2 <= s_bph; hex1 <= s_bpt; hex0 <= s_bpu; 
        else
            hex5 <= "1000110"; hex4 <= get_char(d_child);
            hex3 <= "0001000"; hex2 <= get_char(d_adult);
            hex1 <= "1001111"; hex0 <= get_char(d_elder);
        end if;
    end process;

    -- GERADOR DE TICK (Clock Enable)

    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if rst_n = '0' then
                div_cnt <= 0;
                tick_enable <= '0';
            else
                tick_enable <= '0'; -- Default
                if div_cnt >= 531914 then 
                    div_cnt <= 0;
                    tick_enable <= '1'; -- Gera um pulso de 1 ciclo
                else
                    div_cnt <= div_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- MÁQUINA DE ESTADOS 1 (BURST / CICLOS 6/2)
    
    -- Registrador de Estado)
    process(clk_50mhz, rst_n)
    begin
        if rst_n = '0' then
            burst_state <= ST_IDLE_2; -- Reset Assíncrono
            burst_cnt   <= 0;
        elsif rising_edge(clk_50mhz) then
            if tick_enable = '1' then
                burst_state <= next_burst_state; -- Atualiza Estado
                burst_cnt   <= next_burst_cnt;   -- Atualiza Contador auxiliar
            end if;
        end if;
    end process;

    -- Lógica de Próximo Estado e Saída
    process(burst_state, burst_cnt, sw_mode)
    begin
        -- Valores Default
        next_burst_state <= burst_state;
        next_burst_cnt   <= burst_cnt;
        enable_read_node <= '1'; -- Default: lendo

        if sw_mode = '1' then
            case burst_state is
                when ST_IDLE_2 =>
                    enable_read_node <= '0'; -- Saída BAIXO
                    
                    if burst_cnt >= 1 then -- Lógica de transição
                        next_burst_state <= ST_READING_6;
                        next_burst_cnt   <= 0;
                    else
                        next_burst_cnt   <= burst_cnt + 1;
                    end if;

                when ST_READING_6 =>
                    enable_read_node <= '1'; -- Saída ALTO
                    
                    if burst_cnt >= 5 then -- Lógica de transição
                        next_burst_state <= ST_IDLE_2;
                        next_burst_cnt   <= 0;
                    else
                        next_burst_cnt   <= burst_cnt + 1;
                    end if;
            end case;
        else
            -- Modo Contínuo
            next_burst_state <= ST_IDLE_2;
            next_burst_cnt   <= 0;
            enable_read_node <= '1';
        end if;
    end process;

    -- MÁQUINA DE ESTADOS 2 (ECG PICO) E DATAPATH

    -- Registradores de Estado e Dados
    process(clk_50mhz, rst_n)
    begin
        if rst_n = '0' then
            current_state <= ST_IDLE;
            rom_addr <= 0;
            sample_cnt <= 0;
            pat_global_cnt <= 1;
            active_id_tens <= 0; active_id_unit <= 1;
            stored_id_tens <= 0; stored_id_unit <= 0; stored_bpm <= 0;
            peak_timer <= 0;
            active_bpm <= 0;
        elsif rising_edge(clk_50mhz) then
            if tick_enable = '1' then
                if enable_read_node = '1' then
                    
                    -- Atualiza Estado Principal
                    current_state <= next_state; 

                    -- Lógica de Timer
                    if peak_timer < 2000 then 
                         -- Reset do timer ocorre na transição de estado, senão incrementa
                         if current_state = ST_IDLE and sample_data > 3480 then
                             peak_timer <= 0;
                         elsif current_state = ST_MEASURING and sample_data > 3480 then
                             peak_timer <= 0;
                         else
                             peak_timer <= peak_timer + 1; 
                         end if;
                    end if;

                    -- Lógica de Cálculo BPM
                    if current_state = ST_MEASURING and sample_data > 3480 then
                         if peak_timer > 5 then
                              active_bpm <= 7500 / peak_timer;
                         end if;
                    end if;

                    -- Lógica de Troca de Paciente
                    if sample_cnt = 187 then
                        stored_id_tens <= active_id_tens;
                        stored_id_unit <= active_id_unit;
                        stored_bpm     <= active_bpm;
                        sample_cnt     <= 0;
                        
                        -- Lógica de loop global de pacientes
                        if pat_global_cnt = 80 then
                            pat_global_cnt <= 1;
                            rom_addr <= 0;
                            active_id_tens <= 0; active_id_unit <= 1;
                        else
                            pat_global_cnt <= pat_global_cnt + 1;
                            rom_addr <= rom_addr + 1;
                            if active_id_unit = 9 then
                                active_id_unit <= 0;
                                active_id_tens <= active_id_tens + 1;
                            else
                                active_id_unit <= active_id_unit + 1;
                            end if;
                        end if;
                    else
                        sample_cnt <= sample_cnt + 1;
                        rom_addr   <= rom_addr + 1;
                    end if;

                end if; -- fim enable_read
            end if; -- fim tick
        end if; -- fim clock
    end process;

    -- Apenas Lógica de Próximo Estado da FSM Principal
    process(current_state, sample_data)
    begin
        -- Default
        next_state <= current_state;

        case current_state is
            when ST_IDLE =>
                if sample_data > 3480 then
                    next_state <= ST_WAIT_RELEASE;
                end if;

            when ST_WAIT_RELEASE =>
                if sample_data < 2000 then
                    next_state <= ST_MEASURING;
                end if;

            when ST_MEASURING =>
                if sample_data > 3480 then
                    next_state <= ST_WAIT_RELEASE; 
                end if;
        end case;
    end process;

end rtl;