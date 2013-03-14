library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.util.all;

entity execution_unit is

    generic
    (
        gate_delay: time;           -- delay per gate for simulation only
        word_size:  positive;       -- width of data bus in bits
        icc_size:   positive := 2;  -- width of instruction cycle counter
        reg_high:   positive;       -- number of registers
        ram_size:   positive;       -- size of RAM in words
        intr_size:  positive;       -- number of interrupt lines
        ports_in:   positive;       -- number of 8 bit wide input ports
        ports_out:  positive        -- number of 8 bit wide output ports
    );

    port
    (
        clk:           in  std_logic                                         :=            'X';           -- clock
        rst:           in  std_logic                                         :=            'X';           -- rst
        en:            in  std_logic                                         :=            'X';           -- enable

--synopsys synthesis_off
        test_pc:       out unsigned(        (n_bits(ram_size) - 1) downto 0) := (others => '0');          -- program counter
        test_sp:       out unsigned(        (n_bits(ram_size) - 1) downto 0) := (others => '0');          -- stack pointer
        test_sr:       out std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- status register
--synopsys synthesis_on

        reg_a_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register write address
        reg_a_wr:      out std_logic                                         :=            '0';           -- register write
        reg_a_di:      out std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- register write data

        reg_b_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register read address
        reg_b_rd:      out std_logic                                         :=            '0';           -- register read
        reg_b_do:      in  std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- register read data

        reg_c_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register read address
        reg_c_rd:      out std_logic                                         :=            '0';           -- register read
        reg_c_do:      in  std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- register read data

        rom_addr:      out std_logic_vector((n_bits(ram_size) - 1) downto 0) := (others => '0');          -- ROM address to read
        rom_en:        out std_logic                                         :=            '0';           -- ROM enable
        rom_data:      in  std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- ROM data

        ram_addr:      out std_logic_vector((n_bits(ram_size) - 1) downto 0) := (others => '0');          -- RAM address to write
        ram_rd:        out std_logic                                         :=            '0';           -- RAM read
        ram_rdata:     in  std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- RAM data to read
        ram_wr:        out std_logic                                         :=            '0';           -- RAM write
        ram_wdata:     out std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- RAM data to write

        intr:          in  std_logic_vector((       intr_size - 1) downto 0) := (others => 'X');          -- Interrupt lines

        io_in:         in  byte_vector(     (       ports_in  - 1) downto 0) := (others => byte_unknown); -- 8 bit wide input ports
        io_out:        out byte_vector(     (       ports_out - 1) downto 0) := (others => byte_null);    -- 8 bit wide output ports

        alu_si:        out std_logic                                         :=            '0';           -- signed integers
        alu_a_c:       out std_logic                                         :=            '0';           -- A complement
        alu_a_di:      out std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- A data in
        alu_b_c:       out std_logic                                         :=            '0';           -- B complement
        alu_b_di:      out std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- B data in
        alu_c_in:      out std_logic                                         :=            '0';           -- carry in
        alu_s_do:      in  std_logic_vector((       word_size - 1) downto 0) := (others => 'X');          -- sum data out
        alu_c_out:     in  std_logic                                         :=            'X'            -- carry out
    );

end execution_unit;

architecture syn of execution_unit is

    subtype  pc_counter  is    unsigned( n_bits(ram_size)        - 1 downto 0);
    subtype  sp_counter  is    unsigned( n_bits(ram_size)        - 1 downto 0);
    subtype  icc_counter is    unsigned(        icc_size         - 1 downto 0);
    subtype  intr_array  is    std_logic_vector(intr_size        - 1 downto 0);
    subtype  word        is    std_logic_vector(word_size        - 1 downto 0);
    subtype  reg_addr    is    std_logic_vector(n_bits(reg_high) - 1 downto 0);
    
    subtype  reg_type    is    std_logic_vector(word_size - 1  downto 0);
       type  reg_vector  is    array (reg_high downto 2) of reg_type;

    constant word_null:        word                                                         := std_logic_vector(to_unsigned(0, word_size));
    constant pc_reset_value:   pc_counter                                                   := to_unsigned(intr_size, pc_counter'length);
    constant icc_reset_value:  icc_counter                                                  := (others => '0');
    constant top_of_stack:     sp_counter                                                   := (others => '1');
    constant ram_padding_bits: std_logic_vector(word_size - n_bits(ram_size) -  1 downto 0) := (others => '0');
    constant int_padding_bits: std_logic_vector(word_size - n_bits(ram_size) - 17 downto 0) := (others => '0');
    constant io_padding_bits:  std_logic_vector(word_size                    -  9 downto 0) := (others => '0');
    constant intr_null:        intr_array                                                   := (others => '0');
    
    constant reg_zero:         integer                                                      := 0;
    constant reg_pc:           integer                                                      := 1;
    constant reg_sp:           integer                                                      := 2;
    constant reg_sr:           integer                                                      := 3;

    constant intr_en:          integer                                                      := 0;
    constant test:             integer                                                      := 1;
    constant carry:            integer                                                      := 2;
    
    constant reg_null:         reg_addr                                                     := (others => '0');

    signal   opcode:           std_logic_vector(7 downto 0)                                 := (others => '0');
    signal   ins_data:         std_logic_vector(word_size - 9 downto 0)                     := (others => '0');
    signal   curr_pc:          pc_counter                                                   := pc_reset_value;
    signal   next_pc:          pc_counter                                                   := pc_reset_value;
    signal   nxt2_pc:          pc_counter                                                   := pc_reset_value;
    signal   curr_icc:         icc_counter                                                  := icc_reset_value;
    signal   next_icc:         icc_counter                                                  := icc_reset_value;
    signal   curr_sp:          sp_counter                                                   := top_of_stack;
    signal   next_sp:          sp_counter                                                   := top_of_stack;
    signal   nxt2_sp:          sp_counter                                                   := top_of_stack;
    signal   curr_sr:          std_logic_vector(word_size - 1 downto 0)                     := (others => '0');
    signal   next_sr:          std_logic_vector(word_size - 1 downto 0)                     := (others => '0');
    signal   nxt2_sr:          std_logic_vector(word_size - 1 downto 0)                     := (others => '0');
    signal   curr_io_out:      byte_vector((ports_out - 1) downto 0)                        := (others => byte_null);
    signal   next_io_out:      byte_vector((ports_out - 1) downto 0)                        := (others => byte_null);
    signal   intr_flag:        intr_array                                                   := intr_null;
    signal   intr_reset:       intr_array                                                   := intr_null;
    signal   curr_opcode:      std_logic_vector(7 downto 0)                                 := (others => '0');
    signal   next_opcode:      std_logic_vector(7 downto 0)                                 := (others => '0');
    signal   curr_dst:         std_logic_vector(7 downto 0)                                 := (others => '0');
    signal   next_dst:         std_logic_vector(7 downto 0)                                 := (others => '0');
    signal   curr_tmpB:        word                                                         := (others => '0');
    signal   next_tmpB:        word                                                         := (others => '0');
    signal   curr_tmpC:        word                                                         := (others => '0');
    signal   next_tmpC:        word                                                         := (others => '0');
    signal   curr_opc:         reg_addr                                                     := reg_null;
    signal   next_opc:         reg_addr                                                     := reg_null;
    signal   op_a_addr:        reg_addr                                                     := reg_null;
    signal   op_a_di:          word                                                         := word_null;
    signal   op_b_addr:        reg_addr                                                     := reg_null;
    signal   curr_op_b:        reg_addr                                                     := reg_null;
    signal   next_op_b:        reg_addr                                                     := reg_null;
    signal   op_b_do:          word                                                         := word_null;
    signal   op_c_addr:        reg_addr                                                     := reg_null;
    signal   curr_op_c:        reg_addr                                                     := reg_null;
    signal   next_op_c:        reg_addr                                                     := reg_null;
    signal   op_c_do:          word                                                         := word_null;
    
begin

--synopsys synthesis_off
    test_pc                                        <= curr_pc;
    test_sp                                        <= curr_sp;
    test_sr                                        <= curr_sr;
--synopsys synthesis_on
    
    rom_en                                         <= '1'                                                                 after gate_delay;
    rom_addr                                       <= std_logic_vector(next_pc)                                           after gate_delay;
    opcode                                         <= rom_data((word_size - 1) downto (word_size - 8));
    ins_data                                       <= rom_data((word_size - 9) downto              0 );

    io_out                                         <= next_io_out                                                         after gate_delay;

    process (clk, rst)
    begin

        if clk'event and (clk = '1') then

            if (rst = '1') then

                curr_icc                           <= icc_reset_value                                                     after gate_delay;
                curr_sp                            <= top_of_stack                                                        after gate_delay;
                curr_sr                            <= (others => '0')                                                     after gate_delay;
                curr_io_out                        <= (others => byte_null)                                               after gate_delay;
                intr_flag                          <= (others => '0')                                                     after gate_delay;
                curr_pc                            <= pc_reset_value                                                      after gate_delay;
                curr_opcode                        <= (others => '0')                                                     after gate_delay;
                curr_dst                           <= (others => '0')                                                     after gate_delay;
                curr_tmpB                          <= (others => '0')                                                     after gate_delay;
                curr_tmpC                          <= (others => '0')                                                     after gate_delay;
                curr_opc                           <= reg_null                                                            after gate_delay;
                curr_op_b                          <= reg_null                                                            after gate_delay;
                curr_op_c                          <= reg_null                                                            after gate_delay;

            else

                if (en = '1') then

                    curr_icc                       <= next_icc                                                            after gate_delay;
                    curr_sp                        <= nxt2_sp                                                             after gate_delay;
                    curr_sr                        <= nxt2_sr                                                             after gate_delay;
                    curr_io_out                    <= next_io_out                                                         after gate_delay;
                    curr_pc                        <= nxt2_pc                                                             after gate_delay;
                    curr_opcode                    <= next_opcode                                                         after gate_delay;
                    curr_dst                       <= next_dst                                                            after gate_delay;
                    curr_tmpB                      <= next_tmpB                                                           after gate_delay;
                    curr_tmpC                      <= next_tmpC                                                           after gate_delay;
                    curr_opc                       <= next_opc                                                            after gate_delay;
                    curr_op_b                      <= next_op_b                                                           after gate_delay;
                    curr_op_c                      <= next_op_c                                                           after gate_delay;

                end if;
                
                for i in intr'range loop

                    if (intr_reset(i) = '1') then

                        intr_flag(i)               <= '0'                                                                 after gate_delay;

                    elsif (intr(i) = '1') then

                        intr_flag(i)               <= '1'                                                                 after gate_delay;

                    end if;

                end loop;

            end if;

        end if;

    end process;

    process(next_pc, next_sp, next_sr, op_a_addr, op_a_di)
    begin
        nxt2_pc                                    <= next_pc                                                             after gate_delay;
        nxt2_sp                                    <= next_sp                                                             after gate_delay;
        nxt2_sr                                    <= next_sr                                                             after gate_delay;
        reg_a_addr                                 <= reg_null                                                            after gate_delay;
        reg_a_wr                                   <= '0'                                                                 after gate_delay;
        reg_a_di                                   <= word_null                                                           after gate_delay;

        case to_integer(unsigned(op_a_addr)) is
        
            when reg_zero =>
            
                -- Ignore write to register 0
              
            when reg_pc =>

                nxt2_pc                            <= unsigned(op_a_di(pc_counter'range))                                 after gate_delay;
            
            when reg_sp =>

                nxt2_sp                            <= unsigned(op_a_di(sp_counter'range))                                 after gate_delay;
            
            when reg_sr =>

                nxt2_sr                            <= op_a_di                                                             after gate_delay;
            
            when 4 to 255 =>
            
                reg_a_addr                         <= op_a_addr                                                           after gate_delay;
                reg_a_wr                           <= '1'                                                                 after gate_delay;
                reg_a_di                           <= op_a_di                                                             after gate_delay;
            
            when others =>
            
                -- Ignore write to invalid register
            
        end case;

    end process;

    process(op_b_addr)
    begin
        next_op_b                                  <= reg_null                                                            after gate_delay;
        reg_b_addr                                 <= reg_null                                                            after gate_delay;
        reg_b_rd                                   <= '0'                                                                 after gate_delay;

        case to_integer(unsigned(op_b_addr)) is
        
            when reg_zero =>
            
                -- Ignore read from register 0
              
            when reg_pc =>

                next_op_b                          <= op_b_addr                                                           after gate_delay;
            
            when reg_sp =>

                next_op_b                          <= op_b_addr                                                           after gate_delay;
            
            when reg_sr =>

                next_op_b                          <= op_b_addr                                                           after gate_delay;
            
            when 4 to 255 =>
            
                reg_b_addr                         <= op_b_addr                                                           after gate_delay;
                next_op_b                          <= op_b_addr                                                           after gate_delay;
                reg_b_rd                           <= '1'                                                                 after gate_delay;
            
            when others =>
            
                -- Ignore read from invalid register
            
        end case;

    end process;

    process(curr_op_b, curr_pc, curr_sp, curr_sr, reg_b_do)
    begin
        op_b_do                                    <= word_null                                                           after gate_delay;

        case to_integer(unsigned(curr_op_b)) is
        
            when reg_zero =>
            
                -- Ignore read from register 0
              
            when reg_pc =>

                op_b_do(pc_counter'range)          <= std_logic_vector(curr_pc)                                           after gate_delay;
            
            when reg_sp =>

                op_b_do(pc_counter'range)          <= std_logic_vector(curr_sp)                                           after gate_delay;
            
            when reg_sr =>

                op_b_do                            <= curr_sr                                                             after gate_delay;
            
            when 4 to 255 =>
            
                op_b_do                            <= reg_b_do                                                            after gate_delay;
            
            when others =>
            
                -- Ignore read from invalid register
            
        end case;

    end process;

    process(op_c_addr)
    begin
        next_op_c                                  <= reg_null                                                            after gate_delay;
        reg_c_addr                                 <= reg_null                                                            after gate_delay;
        reg_c_rd                                   <= '0'                                                                 after gate_delay;

        case to_integer(unsigned(op_c_addr)) is
        
            when reg_zero =>
            
                -- Ignore read from register 0
              
            when reg_pc =>

                next_op_c                          <= op_c_addr                                                           after gate_delay;
            
            when reg_sp =>

                next_op_c                          <= op_c_addr                                                           after gate_delay;
            
            when reg_sr =>

                next_op_c                          <= op_c_addr                                                           after gate_delay;
            
            when 4 to 255 =>
            
                reg_c_addr                         <= op_c_addr                                                           after gate_delay;
                next_op_c                          <= op_c_addr                                                           after gate_delay;
                reg_c_rd                           <= '1'                                                                 after gate_delay;
            
            when others =>
            
                -- Ignore read from invalid register
            
        end case;

    end process;

    process(curr_op_c, curr_pc, curr_sp, curr_sr, reg_c_do)
    begin
        op_c_do                                    <= word_null                                                           after gate_delay;

        case to_integer(unsigned(curr_op_c)) is
        
            when reg_zero =>
            
                -- Ignore read from register 0
              
            when reg_pc =>

                op_c_do(pc_counter'range)          <= std_logic_vector(curr_pc)                                           after gate_delay;
            
            when reg_sp =>

                op_c_do(pc_counter'range)          <= std_logic_vector(curr_sp)                                           after gate_delay;
            
            when reg_sr =>

                op_c_do                            <= curr_sr                                                             after gate_delay;
            
            when 4 to 255 =>
            
                op_c_do                            <= reg_c_do                                                            after gate_delay;
            
            when others =>
            
                -- Ignore read from invalid register
            
        end case;

    end process;

    process (rst, opcode, ins_data, io_in, ram_rdata, rom_data, intr_flag, curr_pc, curr_icc, curr_sp, curr_sr, 
             op_b_do, op_c_do, curr_io_out, curr_opcode, curr_dst, curr_tmpB, curr_tmpC, curr_opc, alu_s_do, alu_c_out)

        variable addr:     word                         := (others => '0');
        variable idx:      integer                      := 0;
        variable src:      integer                      := 0;
        variable dst:      integer                      := 0;
        variable opa:      integer                      := 0;
        variable opb:      integer                      := 0;
        variable opc:      integer                      := 0;
        variable idx_r:    reg_addr                     := reg_null;
        variable src_r:    reg_addr                     := reg_null;
        variable dst_r:    reg_addr                     := reg_null;
        variable opa_r:    reg_addr                     := reg_null;
        variable opb_r:    reg_addr                     := reg_null;
        variable opc_r:    reg_addr                     := reg_null;
        variable mask_and: std_logic_vector(7 downto 0) := (others => '0');
        variable mask_xor: std_logic_vector(7 downto 0) := (others => '0');

    begin

        ram_rd                                     <=            '0'                                                      after gate_delay;
        ram_addr                                   <= (others => '0')                                                     after gate_delay;
        ram_wr                                     <=            '0'                                                      after gate_delay;
        ram_wdata                                  <= (others => '0')                                                     after gate_delay;
        intr_reset                                 <= (others => '0')                                                     after gate_delay;
        next_icc                                   <= icc_reset_value                                                     after gate_delay;
        next_opcode                                <= curr_opcode                                                         after gate_delay;
        next_dst                                   <= curr_dst                                                            after gate_delay;
        next_tmpB                                  <= curr_tmpB                                                           after gate_delay;
        next_tmpC                                  <= curr_tmpC                                                           after gate_delay;
        next_opc                                   <= curr_opc                                                            after gate_delay;
        op_a_addr                                  <= (others => '0')                                                     after gate_delay;
        op_a_di                                    <= (others => '0')                                                     after gate_delay;
        op_b_addr                                  <= (others => '0')                                                     after gate_delay;
        op_c_addr                                  <= (others => '0')                                                     after gate_delay;

        alu_si                                     <=            '0'                                                      after gate_delay;
        alu_a_c                                    <=            '0'                                                      after gate_delay;
        alu_a_di                                   <= (others => '0')                                                     after gate_delay;
        alu_b_c                                    <=            '0'                                                      after gate_delay;
        alu_b_di                                   <= (others => '0')                                                     after gate_delay;
        alu_c_in                                   <=            '0'                                                      after gate_delay;
    
        if (rst = '1') then

            next_pc                                <= pc_reset_value                                                      after gate_delay;
            next_sp                                <= top_of_stack                                                        after gate_delay;
            next_sr                                <= (others => '0')                                                     after gate_delay;
            next_io_out                            <= (others => byte_null)                                               after gate_delay;

        elsif (intr_flag /= intr_null) and (curr_sr(intr_en) = '1') and (curr_icc = icc_reset_value) then

            next_pc                                <= (others => '0')                                                     after gate_delay;
            next_sp                                <= curr_sp - 1                                                         after gate_delay;
            next_sr                                <= curr_sr                                                             after gate_delay;
            next_sr(intr_en)                       <=            '0'                                                      after gate_delay;
            next_io_out                            <= curr_io_out                                                         after gate_delay;

            ram_wr                                 <=            '1'                                                      after gate_delay;
            ram_addr                               <= std_logic_vector(curr_sp)                                           after gate_delay;
            ram_wdata                              <= curr_sr(15 downto 0) & X"0" & std_logic_vector(curr_pc)             after gate_delay;

            for i in intr'low to intr'high loop

                if (intr_flag(i) = '1') then
                    intr_reset(i)                  <=            '1'                                                      after gate_delay;
                    next_pc                        <= to_unsigned(i, pc_counter'length)                                   after gate_delay;
                    exit;
                end if;
                
            end loop;

        else

            next_pc                                <= curr_pc + 1                                                         after gate_delay;
            next_sp                                <= curr_sp                                                             after gate_delay;
            next_sr                                <= curr_sr                                                             after gate_delay;
            next_io_out                            <= curr_io_out                                                         after gate_delay;
            
            case to_integer(unsigned(opcode)) is
            
                when 16#00#  => -- IUC

                when 16#01#  => -- HUC

                    next_pc                        <= curr_pc                                                             after gate_delay;
                
                when 16#02#  => -- BUC

                    next_pc                        <= unsigned(rom_data(pc_counter'range))                                after gate_delay;
                
                when 16#03#  => -- BIC

                    if (curr_sr(test) = '1') then
                        next_pc                    <= unsigned(rom_data(pc_counter'range))                                after gate_delay;
                    end if;
                
                when 16#04#  => -- SET I/O
                
                    idx                            := to_integer(unsigned(ins_data(23 downto 16)));
                    mask_and                       :=                     ins_data(15 downto  8);
                    mask_xor                       :=                     ins_data( 7 downto  0);
                    next_io_out(idx)               <= (curr_io_out(idx) and mask_and) xor mask_xor                        after gate_delay;

                when 16#05#  => -- TST I/O
                
                    idx                            := to_integer(unsigned(ins_data(23 downto 16)));
                    mask_and                       :=                     ins_data(15 downto  8);
                    mask_xor                       :=                     ins_data( 7 downto  0);

                    if (((io_in(idx) and mask_and) xor mask_xor) = X"00") then
                        next_sr(test)              <= '1'                                                                 after gate_delay;
                    else
                        next_sr(test)              <= '0'                                                                 after gate_delay;
                    end if;

                when 16#06#  => -- BSR

                    next_pc                        <= unsigned(rom_data(pc_counter'range))                                after gate_delay;
                    next_sp                        <= curr_sp - 1                                                         after gate_delay;
                    ram_wr                         <= '1'                                                                 after gate_delay;
                    ram_addr                       <= std_logic_vector(curr_sp)                                           after gate_delay;
                    ram_wdata                      <= ram_padding_bits & std_logic_vector(curr_pc + 1)                    after gate_delay;
                
                when 16#07#  => -- RSR

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        ram_rd                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= std_logic_vector(curr_sp + 1)                                       after gate_delay;
                    else
                        next_pc                    <= unsigned(ram_rdata(pc_counter'range))                               after gate_delay;
                        next_sp                    <= curr_sp + 1                                                         after gate_delay;
                    end if;
                
                when 16#08#  => -- RIR

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        ram_rd                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= std_logic_vector(curr_sp + 1)                                       after gate_delay;
                    else
                        next_pc                    <= unsigned(ram_rdata(pc_counter'range))                               after gate_delay;
                        next_sr(15 downto 0)       <= ram_rdata(word_size - 1 downto word_size - 16)                      after gate_delay;
                        next_sp                    <= curr_sp + 1                                                         after gate_delay;
                    end if;
                
                when 16#09#  => -- SEI

                    next_sr(intr_en)               <= '1'                                                                 after gate_delay;
                
                when 16#0A#  => -- CLI

                    next_sr(intr_en)               <= '0'                                                                 after gate_delay;
                
                when 16#0B#  => -- MTR

                    dst_r                          :=                     ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        ram_rd                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= rom_data((n_bits(ram_size) - 1) downto 0)                           after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= ram_rdata                                                           after gate_delay;
                    end if;
                
                when 16#0C#  => -- RTM

                    src_r                          :=                     ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= src_r                                                               after gate_delay;
                    else
                        ram_wr                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= rom_data((n_bits(ram_size) - 1) downto 0)                           after gate_delay;
                        ram_wdata                  <= op_b_do                                                             after gate_delay;
                    end if;
                
                when 16#0D#  => -- IMTR

                    dst_r                          :=                     ins_data(23 downto 16);
                    src_r                          :=                     ins_data(15 downto  8);
                    idx_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= src_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= idx_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        ram_rd                     <= '1'                                                                 after gate_delay;
                        addr                       := std_logic_vector(unsigned(op_b_do) + unsigned(op_c_do));
                        ram_addr                   <= addr((n_bits(ram_size) - 1) downto 0)                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= ram_rdata                                                           after gate_delay;
                    end if;
                
                when 16#0E#  => -- RTIM

                    dst_r                          :=                     ins_data(23 downto 16);
                    idx_r                          :=                     ins_data(15 downto  8);
                    src_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= dst_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= idx_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_tmpC                  <= std_logic_vector(unsigned(op_b_do) + unsigned(op_c_do));
                        op_b_addr(reg_addr'range)  <= src_r                                                               after gate_delay;
                    else
                        ram_wr                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= curr_tmpC((n_bits(ram_size) - 1) downto 0)                          after gate_delay;
                        ram_wdata                  <= op_b_do                                                             after gate_delay;
                    end if;
                
                when 16#0F#  => -- PSHR

                    src_r                          :=                     ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= src_r                                                               after gate_delay;
                    else
                        next_sp                    <= curr_sp - 1                                                         after gate_delay;
                        ram_wr                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= std_logic_vector(curr_sp)                                           after gate_delay;
                        ram_wdata                  <= op_b_do                                                             after gate_delay;
                    end if;

                when 16#10#  => -- POPR

                    dst_r                          :=                     ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        ram_rd                     <= '1'                                                                 after gate_delay;
                        ram_addr                   <= std_logic_vector(curr_sp + 1)                                       after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= ram_rdata                                                           after gate_delay;
                        next_sp                    <= curr_sp + 1                                                         after gate_delay;
                    end if;

                when 16#11#  => -- RTIO

                    dst                            := to_integer(unsigned(ins_data(23 downto 16)));
                    src_r                          :=                     ins_data(15 downto  8);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= src_r                                                               after gate_delay;
                    else
                        next_io_out(dst)           <= op_b_do(7 downto 0)                                                 after gate_delay;
                    end if;

                when 16#12#  => -- IOTR

                    dst_r                          :=                     ins_data(23 downto 16);
                    src                            := to_integer(unsigned(ins_data(15 downto  8)));
                    op_a_addr                      <= dst_r                                                               after gate_delay;
                    op_a_di                        <= io_padding_bits & io_in(src)                                        after gate_delay;

                when 16#13#  => -- LDLR

                    dst_r := ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= dst_r                                                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= op_b_do(31 downto 16) & ins_data(15 downto 0)                       after gate_delay;
                    end if;

                when 16#14#  => -- LDUR

                    dst_r                          :=                     ins_data(23 downto 16);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= dst_r                                                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= ins_data(15 downto 0) & op_b_do(15 downto 0)                        after gate_delay;
                    end if;

                when 16#15#  => -- ANDR

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= op_b_do and op_c_do                                                 after gate_delay;
                    end if;

                when 16#16#  => -- ORR

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= op_b_do or op_c_do                                                  after gate_delay;
                    end if;

                when 16#17#  => -- XORR

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= op_b_do xor op_c_do                                                 after gate_delay;
                    end if;

                when 16#18#  => -- SRLR

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_opc                   <= opc_r                                                               after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_tmpC                  <= op_b_do                                                             after gate_delay;

                        for i in 1 to 31 loop
                        
                            if (i = to_integer(unsigned(curr_opc))) then
                                next_tmpC          <= word_null((i - 1) downto 0) & op_b_do((word_size - 1) downto i)     after gate_delay;
                                exit;
                            end if;
                                
                        end loop;

                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= curr_tmpC                                                           after gate_delay;
                    end if;

                when 16#19#  => -- SLLR

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_opc                   <= opc_r                                                               after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_tmpC                  <= op_b_do                                                             after gate_delay;

                        for i in 1 to 31 loop
                        
                            if (i = to_integer(unsigned(curr_opc))) then
                                next_tmpC          <= op_b_do((word_size - 1 - i) downto 0) & word_null((i - 1) downto 0) after gate_delay;
                                exit;
                            end if;

                        end loop;

                    else
                        op_a_addr                  <= dst_r                                                               after gate_delay;
                        op_a_di                    <= curr_tmpC                                                           after gate_delay;
                    end if;

                when 16#1A# => -- CMPU

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_dst                   <= dst_r                                                               after gate_delay;
                        next_tmpB                  <= op_b_do                                                             after gate_delay;
                        next_tmpC                  <= op_c_do                                                             after gate_delay;
                    else
                    
                        case to_integer(unsigned(curr_dst(2 downto 0))) is
                        
                            when 0 => -- =
                            
                                if (unsigned(curr_tmpB) = unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 1 => -- /=
                            
                                if (unsigned(curr_tmpB) /= unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 2 => -- <
                            
                                if (unsigned(curr_tmpB) < unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 3 => -- <=
                            
                                if (unsigned(curr_tmpB) <= unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 4 => -- >
                            
                                if (unsigned(curr_tmpB) > unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 5 => -- >=
                            
                                if (unsigned(curr_tmpB) >= unsigned(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 6 => -- = 0
                            
                                if (unsigned(curr_tmpB) = to_unsigned(0, word'length)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 7 => -- /= 0
                            
                                if (unsigned(curr_tmpB) /= to_unsigned(0, word'length)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;
                                
                            when others => -- ignore

                                next_sr(test)  <= '0'                                                                     after gate_delay;

                        end case;

                    end if;

                when 16#1B# => -- CMPS

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_dst                   <= dst_r                                                               after gate_delay;
                        next_tmpB                  <= op_b_do                                                             after gate_delay;
                        next_tmpC                  <= op_c_do                                                             after gate_delay;
                    else
                    
                        case to_integer(unsigned(curr_dst(2 downto 0))) is
                        
                            when 0 => -- =
                            
                                if (signed(curr_tmpB) = signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 1 => -- /=
                            
                                if (signed(curr_tmpB) /= signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 2 => -- <
                            
                                if (signed(curr_tmpB) < signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 3 => -- <=
                            
                                if (signed(curr_tmpB) <= signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 4 => -- >
                            
                                if (signed(curr_tmpB) > signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 5 => -- >=
                            
                                if (signed(curr_tmpB) >= signed(curr_tmpC)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 6 => -- = 0
                            
                                if (signed(curr_tmpB) = to_signed(0, word'length)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;

                            when 7 => -- /= 0
                            
                                if (signed(curr_tmpB) /= to_signed(0, word'length)) then
                                    next_sr(test)  <= '1'                                                                 after gate_delay;
                                else
                                    next_sr(test)  <= '0'                                                                 after gate_delay;
                                end if;
                                
                            when others => -- ignore

                                next_sr(test)  <= '0'                                                                     after gate_delay;

                        end case;

                    end if;

                when 16#20# to 16#27# => -- ALUU

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_opcode                <= opcode                                                              after gate_delay;
                        next_dst                   <= dst_r                                                               after gate_delay;
                        next_tmpB                  <= op_b_do                                                             after gate_delay;
                        next_tmpC                  <= op_c_do                                                             after gate_delay;
                    else
                        alu_si                     <= '0'                                                                 after gate_delay;
                        alu_a_c                    <= curr_opcode(2)                                                      after gate_delay;
                        alu_a_di                   <= curr_tmpB                                                           after gate_delay;
                        alu_b_c                    <= curr_opcode(1)                                                      after gate_delay;
                        alu_b_di                   <= curr_tmpC                                                           after gate_delay;
                        alu_c_in                   <= curr_opcode(0)                                                      after gate_delay;
                        op_a_addr                  <= curr_dst                                                            after gate_delay;
                        op_a_di                    <= alu_s_do                                                            after gate_delay;
                        next_sr(carry)             <= alu_c_out                                                           after gate_delay;
                    end if;

                when 16#28# to 16#2F# => -- ALUS

                    dst_r                          :=                     ins_data(23 downto 16);
                    opb_r                          :=                     ins_data(15 downto  8);
                    opc_r                          :=                     ins_data( 7 downto  0);

                    if (curr_icc = 0) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        op_b_addr(reg_addr'range)  <= opb_r                                                               after gate_delay;
                        op_c_addr(reg_addr'range)  <= opc_r                                                               after gate_delay;
                    elsif (curr_icc = 1) then
                        next_pc                    <= curr_pc                                                             after gate_delay;
                        next_icc                   <= curr_icc + 1                                                        after gate_delay;
                        next_opcode                <= opcode                                                              after gate_delay;
                        next_dst                   <= dst_r                                                               after gate_delay;
                        next_tmpB                  <= op_b_do                                                             after gate_delay;
                        next_tmpC                  <= op_c_do                                                             after gate_delay;
                    else
                        alu_si                     <= '1'                                                                 after gate_delay;
                        alu_a_c                    <= curr_opcode(2)                                                      after gate_delay;
                        alu_a_di                   <= curr_tmpB                                                           after gate_delay;
                        alu_b_c                    <= curr_opcode(1)                                                      after gate_delay;
                        alu_b_di                   <= curr_tmpC                                                           after gate_delay;
                        alu_c_in                   <= curr_opcode(0)                                                      after gate_delay;
                        op_a_addr                  <= curr_dst                                                            after gate_delay;
                        op_a_di                    <= alu_s_do                                                            after gate_delay;
                        next_sr(carry)             <= alu_c_out                                                           after gate_delay;
                    end if;

                when others => -- Default is IUC
                
            end case;

        end if;
        
    end process;

end syn;
