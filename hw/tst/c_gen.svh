//import common::*;

// AXIS Generator
class c_gen;
  // Send to driver (mailbox)
  mailbox gen2drv;

  // Params
  c_struct_t params;

  // Completion
  event done;
  
  //
  // C-tor
  //
  function new(mailbox gen2drv, input c_struct_t params);
    this.gen2drv = gen2drv;
    this.params = params;
  endfunction
  
  //
  // Run
  // --------------------------------------------------------------------------
  // This is the function to edit if any custom stimulus is needed. 
  // By default it will generate random stimulus n_trs times.
  // --------------------------------------------------------------------------
  //
  
  task run();
    c_trs trs;
    int 	 fd, ch, i, j;

    string folder = "../../../../../../../data/simulation/";
    int num_files = 8;

  string filenames[8] = {
    "values000.bin",
    // "values000.snappy",
    // "values001.bin",
    // "values001.snappy",
    "int32_pages/values001_DATA_PAGE_PLAIN_h0.bin",
    "int32_pages/values000_DICTIONARY_PAGE_PLAIN_h0.bin",
    "int32_pages/values001_DATA_PAGE_RLE_DICTIONARY_h0.bin",
    "int32_pages/values001_DATA_PAGE_RLE_DICTIONARY_h0.bin",
    "int32_pages/values000_DATA_PAGE_PLAIN_h0.bin",
    "bool_pages/values000_DATA_PAGE_PLAIN_h0.bin",
    "int32_pages/values001_DATA_PAGE_PLAIN_h0.bin"

    // "int32_pages/values001_DATA_PAGE_PLAIN_h2f.bin",
    // "int32_pages/values000_DATA_PAGE_PLAIN_h2f.bin",
    // "int32_pages/values000_DICTIONARY_PAGE_PLAIN_h10.bin",
    // "int32_pages/values001_DATA_PAGE_RLE_DICTIONARY_h2d.bin",
    // "int64_pages/values000_DICTIONARY_PAGE_PLAIN_h10.bin",
    // "int64_pages/values001_DATA_PAGE_RLE_DICTIONARY_h3d.bin",
    // "int64_pages/values000_DATA_PAGE_PLAIN_h3f.bin"
  };


    #(params.delay*CLK_PERIOD);

  for (i = 0; i < num_files; i++) begin
    string filename = filenames[i];
    $display("opening file %s", filename);
    fd = $fopen({folder, filename}, "rb");

    j = 0;
    trs = new();
    trs.tkeep = 64'b0; // assuming 512-bit (64 byte) TDATA, initialize TKEEP to zero

    while (1) begin
      ch = $fgetc(fd);

      if (j >= 64 || ch == -1) begin
        trs.tlast = ch == -1 ? 1 : 0;
        trs.display("Gen");
        gen2drv.put(trs);
        if (ch == -1) begin
          break;
        end

        j = 0;
        trs = new();
        trs.tkeep = 64'b0; // reset tkeep for next transaction
      end

      trs.tdata[j*8+:8] = ch[7:0];
      trs.tkeep[j] = 1'b1; // mark this byte as valid
      j++;
    end

    $fclose(fd);
  end
    -> done;
  endtask

endclass
