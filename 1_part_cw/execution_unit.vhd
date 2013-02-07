library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.util.all;

entity execution_unit is

    generic
    (
        gate_delay: time;     -- delay per gate for simulation only
        word_size:  positive; -- width of data bus in bits
        rom_size:   positive; -- size of ROM in words
        ports_in:   positive; -- number of 8 bit wide input ports
        ports_out:  positive  -- number of 8 bit wide output ports
    );

    port
    (
        clk:           in  std_logic                                             :=            'X';  -- clock
        rst:           in  std_logic                                             :=            'X';  -- rst
        en:            in  std_logic                                             :=            'X';  -- enable

--synopsys synthesis_off
        test_pc:       out unsigned((n_bits(rom_size) - 1) downto 0)             := (others => 'X'); -- program counter
        test_opcode:   out std_logic_vector(7 downto 0)                          := (others => 'X'); -- instruction opcode
        test_ins_data: out std_logic_vector(word_size - 9 downto 0)              := (others => 'X'); -- instruction data
--synopsys synthesis_on

        rom_en:        out std_logic                                             	:=            'X';  -- ROM enable (set high when wanting to read)
        rom_addr:      out std_logic_vector((n_bits(rom_size - 1) - 1) downto 0) := (others => 'X'); -- ROM address to read
        rom_data:      in  std_logic_vector((word_size - 1) downto 0)            := (others => 'Z'); -- ROM data (the 8 digit hex word)

        io_in:         in  byte_vector((ports_in - 1) downto 0)                  := (others => byte_unknown); -- 8 bit wide input ports (buttons/switches/dcf/msf/rx)
        io_out:        out byte_vector((ports_out - 1) downto 0)                 := (others => byte_null)     -- 8 bit wide output ports

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
  
  
  signal io_out_port: std_logic_vector(7 downto 0) := (others => 'X');
  signal and_argument: std_logic_vector(7 downto 0) := (others => 'X');
  signal xor_argument: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal curr_test_pc: std_logic_vector((n_bits(rom_size) - 1) downto 0) := (others => 'X');
  signal next_test_pc: std_logic_vector((n_bits(rom_size) - 1) downto 0) := (others => 'X');
  
  signal somesig: std_logic := '0';
  
 -- signal first_inst: std_logic := '1';
  --signal next_first_inst: std_logic := '1';
  
  signal internal_test_ins_data: std_logic_vector(word_size - 9 downto 0) := (others => 'X');
  
  signal test_flag: std_logic := 'X';
  signal next_test_flag: std_logic := 'X';
  
  signal delay: std_logic := '1';
  signal next_delay: std_logic := '1';
  
  type states is (inhibit_a, inhibit_b);
  
  signal current_state:		states 																 := inhibit_a;
  signal next_state:			states 																 := inhibit_a;
  
  signal inhibitor: std_logic := '1';
  signal next_inhibitor: std_logic := '1';
  
  signal inhibit_flag: std_logic := '0';
  signal next_inhibit_flag: std_logic := '0';
  
 --signal io_out_testing_sig: std_logic_vector(byte_vector((ports_in - 1) downto 0) downto 0) := (others => '0');
  signal and_arg_testing_sig: std_logic_vector(7 downto 0) := (others => 'X');
  signal xor_arg_testing_sig: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal b1: std_logic_vector(7 downto 0) := "00100100";
  signal b2: std_logic_vector(7 downto 0) := "00100000";
  signal b3: std_logic_vector(7 downto 0) := "00100000";
  
  
  --signal lhs: std_logic_vector(7 downto 0);
  
  --signal left_hand_side: std_logic_vector(byte_vector(((ports_in - 1) downto 0)(to_integer(unsigned(std_logic_vector(7 downto 0)))))) := (others => 'X');
  
  
  
begin

rom_en <= '1';
io_out <= internal_io_out;	
rom_addr <= std_logic_vector(next_test_pc);
test_pc <= (unsigned(curr_test_pc)	);
test_opcode <= internal_opcode;
internal_opcode <= rom_data(31 downto 24);
io_out_port <= rom_data(23 downto 16);
and_argument <= rom_data(15 downto 8);
xor_argument <= rom_data(7 downto 0);
internal_test_ins_data <= rom_data(23 downto 0);
test_ins_data <= internal_test_ins_data;

  
  
  process(clk, rst)
  begin
  
  	if (rst = '1') then -- If reset
  	
  		--curr_rom_en <= 'X';
  		curr_sample_io_out <= (others => byte_null);
  		curr_test_pc <= (others => '0');
  		--first_inst <= '1';
  		test_flag <= 'X';
  		delay <= '1';
  		current_state <= inhibit_a;
  		inhibitor <= '1';
  		--inhibit_flag <= '0';
  	
		elsif clk'event and (clk = '1') then	--On clock ri
		
			--curr_rom_en <= next_rom_en;
			curr_sample_io_out <= next_sample_io_out;
			curr_test_pc <= next_test_pc;
			current_state <= next_state;
			--first_inst <= next_first_inst;
			--rom_en <= '1';
			test_flag <= next_test_flag;
			delay <= next_delay;
			inhibitor <= next_inhibitor;
			
			
			if(delay = '1') then
			
				curr_test_pc <= (others => '0');
				next_delay <= '0';
				
  		end if;
  		
  	
			
		end if;
  
  end process;
  
  process(internal_io_out, inhibit_flag, curr_sample_io_out)
  begin
  
  	if(inhibit_flag = '1') then
  	
  		next_sample_io_out <= curr_sample_io_out;
  		
  	else
  	
  		next_sample_io_out <= internal_io_out;
  		
  	end if;	
  	
  end process;
  		

  
  process(delay, io_in, rst, test_flag, internal_test_ins_data, curr_sample_io_out, io_out_port, and_argument, xor_argument, curr_test_pc, internal_opcode)
  begin
  
  	--if(std_logic_vector((b1 and b2) xor b3) = "00000000") then
  	--	test_one <= '1';
  	--else
 		--	test_one <= '0';
  --	end if;
  		
  
			next_test_pc <= curr_test_pc;
			--next_io_out <= curr_io_out;
			inhibit_flag <= '0';
			next_test_flag <= test_flag;
		
			if (internal_opcode = "00000000") then --IUC
				--stuff
				
			elsif (internal_opcode = "00000001") then --HUC
				--stuff
				
			elsif (internal_opcode = "00000010") then --BUC
				next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(rom_size) - 1) downto 0));
				
			elsif (internal_opcode = "00000011") then --BIC
			
				if(test_flag = '1') then
																								
					next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(rom_size) - 1) downto 0));
				
				elsif(test_flag = '0') then

					next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				
				end if;
			
				--next_test_flag <= 'X';
				
			elsif (internal_opcode = "00000100") then --SETO
				internal_io_out(to_integer(unsigned(io_out_port))) <= std_logic_vector((curr_sample_io_out(to_integer(unsigned(io_out_port)))) and and_argument) xor xor_argument;
			  next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
			  
			  inhibit_flag <= '1';			    	  
				
			elsif (internal_opcode = "00000101") then --TSTI
			
				next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);

				and_arg_testing_sig <= and_argument;
				xor_arg_testing_sig <= xor_argument;
								



				if ((std_logic_vector((io_in(to_integer(unsigned(io_out_port))) and and_argument) xor xor_argument)) = "00000000") then --It is zero, branch
			
					next_test_flag <= '1';
				
				else --Don't branch
				
					next_test_flag <= '0';
			
				end if;
				
			end if;
			
			if(rst = '1' or delay = '1') then
				next_test_pc <= (others => '0');
			end if;
			
  end process;
  
  
    
end syn;
