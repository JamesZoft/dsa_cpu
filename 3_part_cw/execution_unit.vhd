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
        test_opcode:   out std_logic_vector(7 downto 0)                          := (others => 'X'); -- instruction opcode
        test_ins_data: out std_logic_vector(word_size - 9 downto 0)              := (others => 'X'); -- instruction data
--synopsys synthesis_on

        reg_a_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register write address
        reg_a_wr:      out std_logic                                         :=            '0';           -- register write
        reg_a_di:      out std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- register write data

        reg_b_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register read address
        reg_b_rd:      out std_logic                                         :=            '0';           -- register read
        reg_b_do:      in  std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- register read data

        reg_c_addr:    out std_logic_vector((n_bits(reg_high) - 1) downto 0) := (others => '0');          -- register read address
        reg_c_rd:      out std_logic                                         :=            '0';           -- register read
        reg_c_do:      in  std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- register read data

        rom_addr:      out std_logic_vector((n_bits(ram_size) - 1) downto 0) := (others => '0');          -- ROM address to read
        rom_en:        out std_logic                                         :=            '0';           -- ROM enable
        rom_data:      in  std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- ROM data

        ram_addr:      out std_logic_vector((n_bits(ram_size) - 1) downto 0) := (others => '0');          -- RAM address to write
        ram_rd:        out std_logic                                         :=            '0';           -- RAM read
        ram_rdata:     in  std_logic_vector((       word_size - 1) downto 0) := (others => '0');          -- RAM data to read
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
        alu_c_out:     in  std_logic                                         :=            '0'            -- carry out
    );

end execution_unit;

architecture syn of execution_unit is

  signal curr_rom_en: std_logic	:= 'X';
  signal next_rom_en: std_logic := 'X';
  
  signal curr_sample_io_out: byte_vector((ports_out - 1) downto 0)  := (others => byte_null);
  signal next_sample_io_out: byte_vector((ports_out - 1) downto 0)  := (others => byte_null);
  signal internal_io_out : byte_vector((ports_out - 1) downto 0) := (others => byte_null);
  
  signal internal_opcode: std_logic_vector(7 downto 0) := (others => 'X');
  signal next_test_opcode: std_logic_vector(7 downto 0) := (others => 'X');
  signal curr_test_opcode: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal start_of_rom: std_logic_vector((n_bits(ram_size) - 1) downto 0) := std_logic_vector(to_unsigned(8, n_bits(ram_size)));
  
  
  signal io_out_port: std_logic_vector(7 downto 0) := (others => 'X');
  signal and_argument: std_logic_vector(7 downto 0) := (others => 'X');
  signal xor_argument: std_logic_vector(7 downto 0) := (others => 'X');
  signal address_or_value: std_logic_vector(15 downto 0) := (others => 'X');
  
  signal curr_test_pc: std_logic_vector((n_bits(ram_size) - 1) downto 0) := start_of_rom;			
  																																							
  signal next_test_pc: std_logic_vector((n_bits(ram_size) - 1) downto 0) := start_of_rom;
  
  signal internal_test_ins_data: std_logic_vector(word_size - 9 downto 0) := (others => 'X');
  
  signal test_flag: std_logic := 'X';
  signal next_test_flag: std_logic := 'X';
  
  signal curr_test_sp: unsigned((n_bits(ram_size) - 1) downto 0) := (others => '1');
  signal next_test_sp: unsigned((n_bits(ram_size) - 1) downto 0) := (others => '1');
  
  signal curr_test_sr: std_logic_vector((word_size - 1) downto 0) := (others => '0');
  signal next_test_sr: std_logic_vector((word_size - 1) downto 0) := (others => '0');
  
  signal curr_interrupt_register: std_logic_vector(7 downto 0) := (others => '0');
  signal next_interrupt_register: std_logic_vector(7 downto 0) := (others => '0');
  
  signal two_cycle_counter: std_logic := '0';
  signal next_two_cycle_counter: std_logic := '0';
  
  signal three_cycle_counter: integer := 2;
  signal next_three_cycle_counter: integer := 2;
  
  signal register_storage: std_logic_vector((word_size - 1) downto 0) := (others => 'X');
  signal next_register_storage: std_logic_vector((word_size - 1) downto 0) := (others => 'X');
  
  signal pop_reg_is_pc: std_logic := '0';
  signal next_pop_reg_is_pc: std_logic := '0';
  
  signal intermediate_value_reg : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  signal next_intermediate_value_reg : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  signal intermediate_value_2_reg : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  signal next_intermediate_value_2_reg : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  signal operator_for_cmp : std_logic_vector(7 downto 0) := (others => 'X');
  
  signal test: std_logic := '0';
    
begin

rom_en <= '1' after gate_delay;
io_out <= internal_io_out;	
rom_addr <= std_logic_vector(next_test_pc);
--synopsys synthesis_off
test_pc <= (unsigned(curr_test_pc)	);
test_opcode <= internal_opcode;
test_ins_data <= internal_test_ins_data;
test_sp <= curr_test_sp;
test_sr <= curr_test_sr;
--synopsys synthesis_on
internal_opcode <= rom_data(31 downto 24);
operator_for_cmp <= rom_data(23 downto 16);
io_out_port <= rom_data(23 downto 16);
and_argument <= rom_data(15 downto 8);
xor_argument <= rom_data(7 downto 0);
internal_test_ins_data <= rom_data(23 downto 0);
address_or_value <= rom_data(15 downto 0);
  
  
  process(clk, rst, start_of_rom)
  begin
  
  	if (rst = '1') then -- If reset
  	
  		curr_sample_io_out <= (others => byte_null);
  		curr_test_pc <= start_of_rom;
  		test_flag <= 'X';
  		curr_test_sp <= (others => '1');
  		curr_test_sr <= (others => '0');
  		curr_interrupt_register <= (others => '0');
  		two_cycle_counter <= '0';
  		three_cycle_counter <= 2;
  		register_storage <= (others => '0');
  		pop_reg_is_pc <= '0';
  		intermediate_value_reg <= (others => '0');
  		intermediate_value_2_reg <= (others => '0');
  	
		elsif clk'event and (clk = '1') then	--On clock ri
		
			curr_sample_io_out <= next_sample_io_out;
			curr_test_pc <= next_test_pc;
			test_flag <= next_test_flag;
			curr_test_sp <= next_test_sp;
			curr_test_sr <= next_test_sr;
			curr_interrupt_register <= next_interrupt_register;
			two_cycle_counter <= next_two_cycle_counter;
			three_cycle_counter <= next_three_cycle_counter;
			register_storage <= next_register_storage;
			pop_reg_is_pc <= next_pop_reg_is_pc;
			intermediate_value_reg <= next_intermediate_value_reg;
			intermediate_value_2_reg <= next_intermediate_value_2_reg;
			
		end if;
  
  end process;
  
  process(internal_io_out,  curr_sample_io_out) --Sampling process for io_out with an inhibitor for when we want to change the value
  begin
  	
  		next_sample_io_out <= internal_io_out;
  	
  end process;
  
  process(alu_c_out, start_of_rom, operator_for_cmp, alu_s_do, intermediate_value_reg, intermediate_value_2_reg, address_or_value, pop_reg_is_pc, register_storage, reg_c_do, reg_b_do, three_cycle_counter, two_cycle_counter, intr, curr_interrupt_register, ram_rdata, curr_test_sp, io_in, rst, test_flag, internal_test_ins_data, curr_sample_io_out, io_out_port, and_argument, xor_argument, curr_test_pc, internal_opcode, curr_test_sp, curr_test_sr)
  
  	variable intermediate_value : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  	variable intermediate_value_2 : std_logic_vector((       word_size - 1) downto 0) := (others => 'X');
  	
  begin
  
			next_test_pc <= curr_test_pc;
			next_test_sp <= curr_test_sp;
			next_test_sr <= curr_test_sr;
			next_test_flag <= test_flag;
			ram_wr <= '0';
			ram_rd <= '0';
			ram_addr <=  (others => '0');
			ram_wdata <= (others => '0');
			internal_io_out <= curr_sample_io_out;
			next_interrupt_register <= curr_interrupt_register;
			next_two_cycle_counter <= two_cycle_counter;
			next_three_cycle_counter <= 2;
			reg_a_addr <= (others => '0');
      reg_a_wr <= '0';
      reg_a_di <= (others => '0');
      reg_b_addr <= (others => '0');
      reg_b_rd <= '0';
      reg_c_addr <= (others => '0');
			reg_c_rd <= '0';
			pop_reg_is_pc <= '0';
			test <= '0';
			alu_si <= '0';
      alu_a_c <= '0'; 
      alu_a_di <= (others => '0'); 
      alu_b_c <= '0';
      alu_b_di <= (others => '0');
      alu_c_in <= '0';
      intermediate_value := (others => '0');
      intermediate_value_2 := (others => '0');
      next_intermediate_value_reg <= intermediate_value_reg;
      next_intermediate_value_2_reg <= intermediate_value_2_reg;
      next_register_storage <= register_storage;
		
			if (intr /= "00000000") then
				if (intr(7) = '1') then
					next_interrupt_register(7) <= '1';
				end if;
				
				if (intr(6) = '1') then
					next_interrupt_register(6) <= '1';
				end if;
				
				if (intr(5) = '1') then
					next_interrupt_register(5) <= '1';
				end if;
				
				if (intr(4) = '1') then
					next_interrupt_register(4) <= '1';
				end if;
				
				if (intr(3) = '1') then
					next_interrupt_register(3) <= '1';
				end if;
				
				if (intr(2) = '1') then
					next_interrupt_register(2) <= '1';
				end if;
				
				if (intr(1) = '1') then
					next_interrupt_register(1) <= '1';
				end if;
				
				if (intr(0) = '1') then
					next_interrupt_register(0) <= '1';
				end if;
			end if;
					
			if (curr_interrupt_register /= "00000000") and (curr_test_sr(0) = '1') and (two_cycle_counter = '0') and (three_cycle_counter = 2) then
				next_test_sr(0) <= '0';
			
				ram_wr <= '1'; --enable RAM writing
				ram_addr <= std_logic_vector(curr_test_sp);
				ram_wdata((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(unsigned(curr_test_pc)); 
				ram_wdata((word_size - 1) downto (word_size/2)) <= curr_test_sr(15 downto 0);
				next_test_sp <= (curr_test_sp - 1); 
			
				if (curr_interrupt_register(0) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(0, n_bits(ram_size-1)));
					next_interrupt_register(0) <= '0';
				
				elsif (curr_interrupt_register(1) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(1, n_bits(ram_size-1)));
					next_interrupt_register(1) <= '0';
				
				elsif (curr_interrupt_register(2) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(2, n_bits(ram_size-1)));
					next_interrupt_register(2) <= '0';
				
				elsif (curr_interrupt_register(3) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(3, n_bits(ram_size-1)));
					next_interrupt_register(3) <= '0';
				
				elsif (curr_interrupt_register(4) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(4, n_bits(ram_size-1)));
					next_interrupt_register(4) <= '0';
				
				elsif (curr_interrupt_register(5) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(5, n_bits(ram_size-1)));
					next_interrupt_register(5) <= '0';
				
				elsif (curr_interrupt_register(6) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(6, n_bits(ram_size-1)));
					next_interrupt_register(6) <= '0';
				
				elsif (curr_interrupt_register(7) = '1') then
					next_test_pc <= std_logic_vector(to_unsigned(7, n_bits(ram_size-1)));
					next_interrupt_register(7) <= '0';
				end if;
				
			else
				
				test <= '1';
				if (internal_opcode = X"00") then --IUC
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
			
				elsif (internal_opcode = X"01") then --HUC
					--stuff
			
				elsif (internal_opcode = X"02") then --BUC
					next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(ram_size) - 1) downto 0));
			
				elsif (internal_opcode = X"03") then --BIC
		
					if(test_flag = '1') then
																							
						next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(ram_size) - 1) downto 0));
			
					elsif(test_flag = '0') then

						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
			
					end if;
			
				elsif (internal_opcode = X"04") then --SETO
					internal_io_out(to_integer(unsigned(io_out_port))) <= std_logic_vector((curr_sample_io_out(to_integer(unsigned(io_out_port)))) and and_argument) xor xor_argument;
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				

			
				elsif (internal_opcode = X"05") then --TSTI
		
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);

					if ((std_logic_vector((io_in(to_integer(unsigned(io_out_port))) and and_argument) xor xor_argument)) = "00000000") then --It is zero, branch
		
						next_test_flag <= '1';
						next_test_sr(1) <= '1';
			
					else --Don't branch
			
						next_test_flag <= '0';
						next_test_sr(1) <= '0';
		
					end if;
			
				elsif (internal_opcode = X"06") then --BSR
			
					ram_wr <= '1'; --enable RAM writing
					ram_addr <= std_logic_vector(curr_test_sp); --set the first RAM address to be written to, to be the current stack pointer (initialised to "1111111")
					ram_wdata((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(unsigned(curr_test_pc) + 1); --set the data to be written to the current program counter + 1
					next_test_sp <= (curr_test_sp - 1); --decrement the stack pointer
					next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(ram_size) - 1) downto 0)); --set the program counter to the address of the BSR command
			
				elsif (internal_opcode = X"07") then --RSR
					 --set the ram address to be written to, to be the current stack pointer - 1 (curr stack pointer points to the next empty address in RAM)
			    
			    if(two_cycle_counter = '0') then
			    
			    	next_two_cycle_counter <= '1';
			    	ram_rd <= '1';
						ram_addr <=  std_logic_vector(curr_test_sp + 1);
						
			    else
			    
					  next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0); --set program counter to the data stored in ram 
					  next_test_sp <= (curr_test_sp + 1); --increment the stack pointer
					  next_two_cycle_counter <= '0';
					  
					end if;
				
		
				elsif (internal_opcode = X"08") then --RIR
			    
			    if(two_cycle_counter = '0') then
						next_two_cycle_counter <= '1';
						
						--enable reading of ram and set address to read to stack pointer + 1
						ram_rd <= '1';
						ram_addr <= std_logic_vector(unsigned(curr_test_sp) + 1);
						
						
					elsif(two_cycle_counter = '1') then
						next_test_sr(0) <= '1'; --enable interrupts
						--increment sp, set pc to the value of the sp+1 that we just told ram to get
						next_test_sp <= (curr_test_sp + 1); 
						next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
				    next_two_cycle_counter <= '0';
						
					end if;
		
				elsif (internal_opcode = X"09") then --SEI
				
					next_test_sr(0) <= '1';
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
		
				elsif (internal_opcode = X"0A") then --CLI
			
					next_test_sr(0) <= '0';
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
					
				elsif(internal_opcode = X"0B") then --MTR R[A] = RAM[addr]
				
					if(two_cycle_counter = '0') then
					
						next_two_cycle_counter <= '1';
						ram_rd <= '1';
						ram_addr <= address_or_value((n_bits(ram_size) - 1) downto 0);
						
					else
					
						reg_a_addr <= io_out_port;
				    reg_a_wr <= '1';
				    reg_a_di <= ram_rdata;
				    next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
				    
				  end if;
				
				elsif(internal_opcode = X"0C") then --RTM RAM[addr] = R[A]
				
				  
					if(two_cycle_counter = '0') then
					
						test <= '1';
						
						if(io_out_port >= X"00") and (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
						
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
						next_two_cycle_counter <= '1';
						
					else
						
						test <= '1';
						if(io_out_port = X"00") then
						
							intermediate_value := (others => '0');
							ram_wdata <= intermediate_value;
						
						elsif(io_out_port = X"01") then
						
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
							ram_wdata <= intermediate_value;
					
						elsif(io_out_port = X"02") then
					
							intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
							ram_wdata <= intermediate_value;
					
						elsif(io_out_port = X"03") then
						
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
							intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
							ram_wdata <= intermediate_value;
							
						else
						
							ram_wdata <= reg_b_do;
							
						end if;
						
						test <= '1';
						ram_wr <= '1';
						ram_addr <= address_or_value((n_bits(ram_size) - 1) downto 0);
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
					
					end if;
					
				
				elsif(internal_opcode = X"0D") then --IMTR R[A] = RAM[R[B] + R[C]]
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_c_rd <= '1';
							reg_c_addr <= xor_argument;
							
						end if;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
					elsif(three_cycle_counter = 1) then
					
						if((xor_argument >= X"00") and (xor_argument <= X"03")) or ((and_argument >= X"00") and (and_argument <= X"03")) then
						
							if(xor_argument = X"00") then
						
								intermediate_value := (others => '0');
							
							elsif(xor_argument = X"01") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(xor_argument = X"02") then
						
								intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(xor_argument = X"03") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
								intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value := reg_c_do;
								
							end if;
							
							if(and_argument = X"00") then
								
								
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) + to_unsigned(0, 8));
							
							elsif(and_argument = X"01") then
							
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_pc));
								intermediate_value_2( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"02") then
						
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_sp));
								intermediate_value_2( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"03") then
							
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_sr));
								intermediate_value_2( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) + unsigned(reg_b_do));
								
							end if;
						
						else
					
							intermediate_value_2 := std_logic_vector(unsigned(reg_b_do) + unsigned(reg_c_do));
						
						
						end if;
						
						next_three_cycle_counter <= 0;
						ram_rd <= '1';
						--intermediate_value <= std_logic_vector(unsigned(reg_b_do) + unsigned(reg_c_do));
						ram_addr <= intermediate_value_2((n_bits(ram_size) - 1) downto 0);
						
						
					elsif(three_cycle_counter = 0) then
					
						
					 	next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
						if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(ram_rdata((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= ram_rdata((word_size - 1) downto 0); 
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= ram_rdata;
						
						end if;
				   
				    next_three_cycle_counter <= 2;
					
					end if;
					
				
				elsif(internal_opcode = X"0E") then --RTIM RAM[R[A] + R[B]] = R[C]
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(io_out_port >= X"00") and (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_c_rd <= '1';
							reg_c_addr <= and_argument;
							
						end if;
					
						
					elsif(three_cycle_counter = 1) then
						
						if((io_out_port >= X"00") and (io_out_port <= X"03")) or ((and_argument >= X"00") and (and_argument <= X"03")) then
						
							if(io_out_port = X"00") then
						
								intermediate_value := (others => '0');
							
							elsif(io_out_port = X"01") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(io_out_port = X"02") then
						
								intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(io_out_port = X"03") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
								intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value := reg_b_do;
								
							end if;
							
							if(and_argument = X"00") then
								
								
								next_register_storage <= std_logic_vector(unsigned(intermediate_value) + to_unsigned(0, 8));
							
							elsif(and_argument = X"01") then
							
								next_register_storage <= std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_pc));
						
							elsif(and_argument = X"02") then
						
								next_register_storage <= std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_sp));
						
							elsif(and_argument = X"03") then
							
								next_register_storage <= std_logic_vector(unsigned(intermediate_value) + unsigned(curr_test_sr));
								
							elsif(and_argument >= X"04") and (and_argument < X"00") then
							
								next_register_storage <= std_logic_vector(unsigned(intermediate_value) + unsigned(reg_c_do));
								
							end if;
						
						else
					
							next_register_storage <= std_logic_vector(unsigned(reg_b_do) + unsigned(reg_c_do));
						
						
						end if;
						
						next_three_cycle_counter <= 0;
						
						if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= xor_argument;
							
						end if;
						
						
					elsif(three_cycle_counter = 0) then
						
						
						if(xor_argument = X"00") then
						
							ram_wdata <= (others => '0');
							
						elsif(xor_argument = X"01") then
							
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
							
						elsif(xor_argument = X"02") then
						
							intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
						
						elsif(xor_argument = X"03") then
							
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
							intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
							
						else
							
							ram_wdata <= reg_b_do;
						
						end if;
						
						ram_wr <= '1';
						ram_addr <= register_storage((n_bits(ram_size) - 1) downto 0);
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"0F") then --PSHR R[A]
				
					if(two_cycle_counter = '0') then
				
						next_two_cycle_counter <= '1';
						
						
						if(io_out_port >= X"00") and (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
					elsif(two_cycle_counter = '1') then
					
						ram_wr <= '1'; 
						ram_addr <= std_logic_vector(curr_test_sp);
						next_test_sp <= (curr_test_sp - 1); 
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
				    
				    next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
						if(io_out_port = X"00") then
						
							ram_wdata <= (others => '0');
							
						elsif(io_out_port = X"01") then
							
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
							
						elsif(io_out_port = X"02") then
						
							intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
							intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
						
						elsif(io_out_port = X"03") then
							
							intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
							intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
						
							ram_wdata <= intermediate_value;
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							ram_wdata <= reg_b_do;
							
						
						end if;
						
					end if;
				
				elsif(internal_opcode = X"10") then --POPR R[A]
				
					if(two_cycle_counter = '0') then
				
						next_two_cycle_counter <= '1';
						
						ram_rd <= '1';
						ram_addr <= std_logic_vector(unsigned(curr_test_sp) + 1);
						
						
					elsif(two_cycle_counter = '1') then
					
						next_test_sp <= (curr_test_sp + 1);
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
						if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(ram_rdata((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= ram_rdata((word_size - 1) downto 0); -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= ram_rdata;
						
						end if;
						
				    next_two_cycle_counter <= '0';
						
					end if;
				
				elsif(internal_opcode = X"11") then --RTIO OUT[port] = R[A]
				
					if(two_cycle_counter = '0') then
						
						
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
						
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
						next_two_cycle_counter <= '1';
						
					else
					
						if(and_argument = X"00") then
								
							internal_io_out(to_integer(unsigned(io_out_port))) <= (others => '0');
						
						elsif(and_argument = X"01") then
						
							internal_io_out(to_integer(unsigned(io_out_port))) <= curr_test_pc(7 downto 0);
					
						elsif(and_argument = X"02") then
					
							internal_io_out(to_integer(unsigned(io_out_port))) <= std_logic_vector(curr_test_sp(7 downto 0));
					
						elsif(and_argument = X"03") then
						
							internal_io_out(to_integer(unsigned(io_out_port))) <= curr_test_sr(7 downto 0);
							
						else
						
							internal_io_out(to_integer(unsigned(io_out_port))) <= reg_b_do(7 downto 0);
							
						end if;
						
						--internal_io_out(to_integer(unsigned(io_out_port))) <= reg_b_do;
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
						
					end if;
				
				elsif(internal_opcode = X"12") then --IOTR R[A] = IN[port]
					

					intermediate_value(7 downto 0) := io_in(to_integer(unsigned(and_argument)));
					intermediate_value(( word_size - 1) downto 8) := (others => '0');
					reg_a_wr <= '1';
					reg_a_addr <= io_out_port;
					reg_a_di <= intermediate_value;
					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
				
				elsif(internal_opcode = X"13") then --LDLR R[A](15 downto 0) = value
					
					--need to get value of register and put in upper 16 bits as well as lower 16, cant do di(15 downto 0)
					
					if(two_cycle_counter = '0') then
					
						next_two_cycle_counter <= '1';
						reg_b_rd <= '1';
						reg_b_addr <= io_out_port;
						
					else
					
						reg_a_addr <= io_out_port;
						reg_a_wr <= '1';
						intermediate_value(15 downto 0) := address_or_value;
						intermediate_value(31 downto 16) := reg_b_do(31 downto 16);
						reg_a_di <= intermediate_value;
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
					
					end if;
				
				elsif(internal_opcode = X"14") then --LDUR R[A](31 downto 16) = value
				
					if(two_cycle_counter = '0') then
				
						next_two_cycle_counter <= '1';
						
					else
					
						reg_a_addr <= io_out_port;
						reg_a_wr <= '1';
						reg_a_di(31 downto 16) <= address_or_value;	
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_two_cycle_counter <= '0';
						
					end if;
				
				elsif(internal_opcode = X"15") then --ANDR R[A] = R[B] and R[C]
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
						if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_c_rd <= '1';
							reg_c_addr <= xor_argument;
							
						end if;
					
						
					elsif(three_cycle_counter = 1) then
						
						if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								intermediate_value := (others => '0');
							
							elsif(and_argument = X"01") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"02") then
						
								intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"03") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
								intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value := reg_b_do;
								
							end if;
							
							if(xor_argument = X"00") then
								
								
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) and to_unsigned(0, 8));
							
							elsif(xor_argument = X"01") then
							
								intermediate_value_2 := (intermediate_value and curr_test_pc);
						
							elsif(xor_argument = X"02") then
						
								intermediate_value_2 := (intermediate_value and std_logic_vector(curr_test_sp));
						
							elsif(xor_argument = X"03") then
							
								intermediate_value_2 := (intermediate_value and curr_test_sr);
								
							else
							
								intermediate_value_2 := (intermediate_value and reg_c_do);
								
							end if;
						
						else
					
							intermediate_value_2 := (reg_b_do and reg_c_do);
						
						
						end if;
						
						next_three_cycle_counter <= 0;
						
						if(io_out_port >= X"00") and (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
						
					elsif(three_cycle_counter = 0) then
						
						
						if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(ram_rdata((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= ram_rdata((word_size - 1) downto 0); -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= ram_rdata;
						
						end if;
						
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"16") then --ORR R[A] = R[B] or R[C]
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
						if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_c_rd <= '1';
							reg_c_addr <= xor_argument;
							
						end if;
					
						
					elsif(three_cycle_counter = 1) then
						
						if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								intermediate_value := (others => '0');
							
							elsif(and_argument = X"01") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"02") then
						
								intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"03") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
								intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value := reg_b_do;
								
							end if;
							
							if(xor_argument = X"00") then
								
								
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) or to_unsigned(0, 8));
							
							elsif(xor_argument = X"01") then
							
								intermediate_value_2 := (intermediate_value or curr_test_pc);
						
							elsif(xor_argument = X"02") then
						
								intermediate_value_2 := (intermediate_value or std_logic_vector(curr_test_sp));
						
							elsif(xor_argument = X"03") then
							
								intermediate_value_2 := (intermediate_value or curr_test_sr);
								
							else
							
								intermediate_value_2 := (intermediate_value or reg_c_do);
								
							end if;
						
						else
					
							intermediate_value_2 := (reg_b_do or reg_c_do);
						
						
						end if;
						
						next_three_cycle_counter <= 0;
						
						if(io_out_port >= X"00") or (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
						
					elsif(three_cycle_counter = 0) then
						
						
						if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(ram_rdata((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= ram_rdata((word_size - 1) downto 0); -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= ram_rdata;
						
						end if;
						
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"17") then --XORR R[A] = R[B] xor R[C]
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
						if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_c_rd <= '1';
							reg_c_addr <= xor_argument;
							
						end if;
					
						
					elsif(three_cycle_counter = 1) then
						
						if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								intermediate_value := (others => '0');
							
							elsif(and_argument = X"01") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_pc;
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"02") then
						
								intermediate_value((n_bits(ram_size) - 1) downto 0) := std_logic_vector(curr_test_sp);
								intermediate_value( ((word_size - 9) -1) downto (n_bits(ram_size))) := (others => '0');
						
							elsif(and_argument = X"03") then
							
								intermediate_value((n_bits(ram_size) - 1) downto 0) := curr_test_sr((n_bits(ram_size) - 1) downto 0);
								intermediate_value( ((word_size - 9) - 1) downto (n_bits(ram_size))) := (others => '0');
								
							else
							
								intermediate_value := reg_b_do;
								
							end if;
							
							if(xor_argument = X"00") then
								
								
								intermediate_value_2 := std_logic_vector(unsigned(intermediate_value) xor to_unsigned(0, 8));
							
							elsif(xor_argument = X"01") then
							
								intermediate_value_2 := (intermediate_value xor curr_test_pc);
						
							elsif(xor_argument = X"02") then
						
								intermediate_value_2 := (intermediate_value xor std_logic_vector(curr_test_sp));
						
							elsif(xor_argument = X"03") then
							
								intermediate_value_2 := (intermediate_value xor curr_test_sr);
								
							else
							
								intermediate_value_2 := (intermediate_value xor reg_c_do);
								
							end if;
						
						else
					
							intermediate_value_2 := (reg_b_do xor reg_c_do);
						
						
						end if;
						
						next_three_cycle_counter <= 0;
						
						if(io_out_port >= X"00") or (io_out_port <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= io_out_port;
							
						end if;
						
						
					elsif(three_cycle_counter = 0) then
						
						
						if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= ram_rdata((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(ram_rdata((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= ram_rdata((word_size - 1) downto 0); -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= ram_rdata;
						
						end if;
						
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"18") then --SRLR R[A] = R[B] slr c
				
					if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
					elsif(three_cycle_counter = 1) then
						
						--intermediate_value <= std_logic_vector(unsigned(reg_b_do) srl to_integer(unsigned(xor_argument)));
						next_three_cycle_counter <= 0;
						
						if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg <= (X"00000" & std_logic_vector(unsigned(curr_test_pc) srl to_integer(unsigned(xor_argument))));
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp srl to_integer(unsigned(xor_argument)));
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(unsigned(curr_test_sr((n_bits(ram_size) - 1) downto 0)) srl to_integer(unsigned(xor_argument)));
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= std_logic_vector(unsigned(reg_b_do) srl to_integer(unsigned(xor_argument)));
								
							end if;
				    
				  elsif(three_cycle_counter = 0) then
				  
				  	reg_a_di <= intermediate_value_reg;
				  	reg_a_addr <= io_out_port;
						reg_a_wr <= '1';
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"19") then --SLLR R[A] = R[B] sll c
				
				  if(three_cycle_counter = 2) then
					
						next_three_cycle_counter <= 1;
						
						if(and_argument >= X"00") and (and_argument <= X"03") then
						
							-- Don't read anything, special rules for what to write are needed
							
						else
							reg_b_rd <= '1';
							reg_b_addr <= and_argument;
							
						end if;
						
					elsif(three_cycle_counter = 1) then
						
						--intermediate_value <= std_logic_vector(unsigned(reg_b_do) srl to_integer(unsigned(xor_argument)));
						next_three_cycle_counter <= 0;
						
						if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg <= (X"00000" & std_logic_vector(unsigned(curr_test_pc) sll to_integer(unsigned(xor_argument))));
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp sll to_integer(unsigned(xor_argument)));
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(unsigned(curr_test_sr((n_bits(ram_size) - 1) downto 0)) sll to_integer(unsigned(xor_argument)));
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= std_logic_vector(unsigned(reg_b_do) sll to_integer(unsigned(xor_argument)));
								
							end if;
				    
				  elsif(three_cycle_counter = 0) then
				  
				  	reg_a_di <= intermediate_value_reg;
				  	reg_a_addr <= io_out_port;
						reg_a_wr <= '1';
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				    next_three_cycle_counter <= 2;
					
					end if;
				
				elsif(internal_opcode = X"1A") then --CMPU R[A] flag{=,/=,<,<=,>,>=,=0,/=0} R[B]
				
				  if(three_cycle_counter = 2) then
				    
				    if(and_argument >= X"00") and (and_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_b_rd <= '1';
						  reg_b_addr <= and_argument;
						
					  end if;
					
					  if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_c_rd <= '1';
						  reg_c_addr <= xor_argument;
						
					  end if;
					  
					  next_three_cycle_counter <= 1;
					  
					elsif(three_cycle_counter = 1) then
					
				  	if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= reg_b_do;
								
							end if;
							
							if(xor_argument = X"00") then
								
								next_intermediate_value_2_reg <= (others => '0');
							
							elsif(xor_argument = X"01") then
							
								next_intermediate_value_2_reg <= ("00000000000000000000" & curr_test_pc);
						
							elsif(xor_argument = X"02") then
						
								next_intermediate_value_2_reg <= ("00000000000000000000" & std_logic_vector(curr_test_sp));
						
							elsif(xor_argument = X"03") then
							
								next_intermediate_value_2_reg <= curr_test_sr;
								
							else
							
								next_intermediate_value_2_reg <= reg_c_do;
								
							end if;
						
						else
						
					    next_intermediate_value_reg <= reg_b_do;  
							next_intermediate_value_2_reg <= reg_c_do;
						
						end if;
						
						next_three_cycle_counter <= 0;
						
					elsif(three_cycle_counter <= 0) then
						
						case operator_for_cmp is
						
						  when "00000000" => --Equals
						    
						    if(unsigned(intermediate_value_reg) = unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
						  
						  when "00000001" => 
						  
						    if(unsigned(intermediate_value_reg) /= unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000010" => 
						  
						    if(unsigned(intermediate_value_reg) < unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000011" => 
						  
						    if(unsigned(intermediate_value_reg) <= unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000100" => 
						  
						    if(unsigned(intermediate_value_reg) > unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000101" => 
						  
						    if(unsigned(intermediate_value_reg) >= unsigned(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000110" => 
						  
						    if(unsigned(intermediate_value_reg) = 0) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000111" => 
						  
						    if(unsigned(intermediate_value_reg) /= 0) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
					   when others =>
					   
					    --do nothing
					      
					end case;
						
						next_three_cycle_counter <= 2;
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
				end if;
				
				elsif(internal_opcode = X"1B") then --CMPS R[A] flag{=,/=,<,<=,>,>=,=0,/=0} R[B]
				
				  if(three_cycle_counter = 2) then
				    
				    if(and_argument >= X"00") and (and_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_b_rd <= '1';
						  reg_b_addr <= and_argument;
						
					  end if;
					
					  if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_c_rd <= '1';
						  reg_c_addr <= xor_argument;
						
					  end if;
					  
					  next_three_cycle_counter <= 1;
					  
					elsif(three_cycle_counter = 1) then
					
				  	if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= reg_b_do;
								
							end if;
							
							if(xor_argument = X"00") then
								
								
								next_intermediate_value_2_reg <= (others => '0');
							
							elsif(xor_argument = X"01") then
							
								next_intermediate_value_2_reg <= ("00000000000000000000" & curr_test_pc);
						
							elsif(xor_argument = X"02") then
						
								next_intermediate_value_2_reg <= ("00000000000000000000" & std_logic_vector(curr_test_sp));
						
							elsif(xor_argument = X"03") then
							
								next_intermediate_value_2_reg <= curr_test_sr;
								
							else
							
								next_intermediate_value_2_reg <= reg_c_do;
								
							end if;
						
						else
					
							next_intermediate_value_2_reg <= reg_c_do;
						
						end if;
						
						next_three_cycle_counter <= 0;
						
					elsif(three_cycle_counter = 0) then
						
						case operator_for_cmp is
						
						  when "00000000" => --Equals
						    
						    if(signed(intermediate_value_reg) = signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
						  
						  when "00000001" => 
						  
						    if(signed(intermediate_value_reg) /= signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000010" => 
						  
						    if(signed(intermediate_value_reg) < signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000011" => 
						  
						    if(signed(intermediate_value_reg) <= signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000100" => 
						  
						    if(signed(intermediate_value_reg) > signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000101" => 
						  
						    if(signed(intermediate_value_reg) >= signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000110" => 
						  
						    if(signed(intermediate_value_reg) /= signed(intermediate_value_2_reg)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
				     when "00000111" => 
						  
						    if(signed(intermediate_value) /= signed(intermediate_value_2)) then
						      next_test_flag <= '1';
						      next_test_sr(1) <= '1';
					      else
						      next_test_flag <= '0';
						      next_test_sr(1) <= '0';
					      end if;
					      
					   when others =>
					   
					    --do nothing
					      
					end case;
						
						next_three_cycle_counter <= 2;
						next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
						
				end if;
				
				elsif(internal_opcode >= X"20") and (internal_opcode <= X"27") then
				
				 if(three_cycle_counter = 2) then
				  
				    if(and_argument >= X"00") and (and_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_b_rd <= '1';
						  reg_b_addr <= and_argument;
						
					  end if;
					
					  if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_c_rd <= '1';
						  reg_c_addr <= xor_argument;
						
					  end if;
					  
					  next_three_cycle_counter <= 1;
					  
					  
					  
					elsif(three_cycle_counter = 1) then
					
				  	if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= reg_b_do;
								
							end if;
							
						  if(xor_argument = X"00") then
						
								next_intermediate_value_2_reg <= (others => '0');
							
							elsif(xor_argument = X"01") then
							
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_2_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(xor_argument = X"02") then
						
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_2_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(xor_argument = X"03") then
							
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_2_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
							  next_intermediate_value_2_reg <= reg_c_do;
							  
							end if;
						
						else
					
					    next_intermediate_value_reg <= reg_b_do;
							next_intermediate_value_2_reg <= reg_c_do;
						
						end if;
						
					 next_three_cycle_counter <= 0;
						
					elsif(three_cycle_counter = 0) then
						
				    alu_si <= '0';
				    alu_a_c <= internal_opcode(2);
            alu_b_c <= internal_opcode(1);
            alu_c_in <= internal_opcode(0);
            
            alu_a_di <= intermediate_value_reg;
            alu_b_di <= intermediate_value_2_reg;
            
            next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
  				  next_three_cycle_counter <= 2;
  				  
  				  if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= alu_s_do((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(alu_s_do((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= alu_s_do; -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= alu_s_do;
						
						end if;
						
  				  next_test_sr(2) <= alu_c_out;
  				  
  				end if;
				
				elsif(internal_opcode >= X"28") and (internal_opcode <= X"2F") then
				
				
				
				  if(three_cycle_counter = 2) then
				  
				    if(and_argument >= X"00") and (and_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_b_rd <= '1';
						  reg_b_addr <= and_argument;
						
					  end if;
					
					  if(xor_argument >= X"00") and (xor_argument <= X"03") then
						
							  -- Don't read anything, special rules for what to write are needed
							
					  else
						  reg_c_rd <= '1';
						  reg_c_addr <= xor_argument;
						
					  end if;
					  
					  next_three_cycle_counter <= 1;
					  
					  
					  
					elsif(three_cycle_counter = 1) then
					
				  	if((and_argument >= X"00") and (and_argument <= X"03")) or ((xor_argument >= X"00") and (xor_argument <= X"03")) then
						
							if(and_argument = X"00") then
						
								next_intermediate_value_reg <= (others => '0');
							
							elsif(and_argument = X"01") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"02") then
						
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(and_argument = X"03") then
							
								next_intermediate_value_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
								next_intermediate_value_reg <= reg_b_do;
								
							end if;
							
						  if(xor_argument = X"00") then
						
								next_intermediate_value_2_reg <= (others => '0');
							
							elsif(xor_argument = X"01") then
							
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_pc;
								next_intermediate_value_2_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(xor_argument = X"02") then
						
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= std_logic_vector(curr_test_sp);
								next_intermediate_value_2_reg( ((word_size - 9) -1) downto (n_bits(ram_size))) <= (others => '0');
						
							elsif(xor_argument = X"03") then
							
								next_intermediate_value_2_reg((n_bits(ram_size) - 1) downto 0) <= curr_test_sr((n_bits(ram_size) - 1) downto 0);
								next_intermediate_value_2_reg( ((word_size - 9) - 1) downto (n_bits(ram_size))) <= (others => '0');
								
							else
							
							  next_intermediate_value_2_reg <= reg_c_do;
							  
							end if;
						
						else
					
					    next_intermediate_value_reg <= reg_b_do;
							next_intermediate_value_2_reg <= reg_c_do;
						
						end if;
						
					 next_three_cycle_counter <= 0;
						
					elsif(three_cycle_counter = 0) then
						
				    alu_si <= '1';
				    alu_a_c <= internal_opcode(2);
            alu_b_c <= internal_opcode(1);
            alu_c_in <= internal_opcode(0);
            
            alu_a_di <= intermediate_value_reg;
            alu_b_di <= intermediate_value_2_reg;
            
            next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
  				  next_three_cycle_counter <= 2;
  				  
  				  if(io_out_port = X"00") then
						
							--Do nothing, can't write to this register
							
						elsif(io_out_port = X"01") then
						
							next_test_pc <= alu_s_do((n_bits(ram_size) - 1) downto 0);
							
						elsif(io_out_port = X"02") then
						
							next_test_sp <= unsigned(alu_s_do((n_bits(ram_size) - 1) downto 0));
						
						elsif(io_out_port = X"03") then
						
							next_test_sr <= alu_s_do; -- line 107 is sr
							
						else
						
							reg_a_wr <= '1';
							reg_a_addr <= io_out_port;
							reg_a_di <= alu_s_do;
						
						end if;
						
  				  next_test_sr(2) <= alu_c_out;
  				  
  				end if;
			
				end if;
				
			end if;
			
			if(rst = '1') then
				next_test_pc <= start_of_rom;
			end if;
			
  end process;

end syn;
