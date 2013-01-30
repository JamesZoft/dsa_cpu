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

        rom_en:        out std_logic                                             :=            'X';  -- ROM enable (set high when wanting to read)
        rom_addr:      out std_logic_vector((n_bits(rom_size - 1) - 1) downto 0) := (others => 'X'); -- ROM address to read
        rom_data:      in  std_logic_vector((word_size - 1) downto 0)            := (others => 'Z'); -- ROM data (the 8 digit hex word)

        io_in:         in  byte_vector((ports_in - 1) downto 0)                  := (others => byte_unknown); -- 8 bit wide input ports (buttons/switches/dcf/msf/rx)
        io_out:        out byte_vector((ports_out - 1) downto 0)                 := (others => byte_null)     -- 8 bit wide output ports

    );

end execution_unit;

architecture syn of execution_unit is

  signal curr_rom_en: std_logic	:= 'X';
  signal next_rom_en: std_logic := 'X';
  
  signal curr_rom_addr: std_logic_vector((n_bits(rom_size - 1) - 1) downto 0) := (others => 'X');
  signal next_rom_addr: std_logic_vector((n_bits(rom_size - 1) - 1) downto 0) := (others => 'X');
  
  signal curr_io_out: byte_vector((ports_out - 1) downto 0) := (others => byte_null);
  signal next_io_out: byte_vector((ports_out - 1) downto 0) := (others => byte_null);
  
  signal opcode: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal io_out_port: std_logic_vector(7 downto 0) := (others => 'X');
  signal and_argument: std_logic_vector(7 downto 0) := (others => 'X');
  signal xor_argument: std_logic_vector(7 downto 0) := (others => 'X');
  
  
  
begin
--curr_rom_en <= '1';
io_out <= curr_io_out;
rom_en <= curr_rom_en;
rom_addr <= curr_rom_addr;
opcode <= rom_data(31 downto 24);
io_out_port <= rom_data(23 downto 16);
and_argument <= rom_data(15 downto 8);
xor_argument <= rom_data(7 downto 0);
  
  process(clk, rst)
  begin
  
  	if (rst = '1') then -- If reset
  	
  		curr_rom_en <= 'X';
  		curr_rom_addr <= (others => 'X');
  		curr_io_out <= (others => byte_null);
  	
		elsif clk'event and (clk = '1') then	--On clock ri
		
			curr_rom_en <= next_rom_en;
			curr_rom_addr <= next_rom_addr;
			curr_io_out <= next_io_out;
			
		end if;
  
  end process;
  
  process(rom_data)
  begin
  	test_opcode <= opcode;
  
  	if (opcode = "00000000") then --IUC
  		--stuff
  		
  	elsif (opcode = "00000001") then --HUC
  		--stuff
  		
  	elsif (opcode = "00000010") then --BUC
  		--stuff
  		
  	elsif (opcode = "00000011") then --BIC
  		--stuff
  		
  	elsif (opcode = "00000100") then --SET0
  		next_io_out(to_integer(io_out_port)) <= (curr_io_out(to_integer(io_out_port)) and and_argument) xor xor_argument; 
  		
  	elsif (opcode = "00000101") then --TSTI
  		--stuff
  		
  	end if;
  		
  
  end process;
  
  
    
end syn;
