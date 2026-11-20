using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;

namespace Antmicro.Renode.Peripherals.SPI
{
    // Single-register control transactions and empty TC6 status exchanges.
    public sealed class LAN8651Control : ISPIPeripheral, IGPIOReceiver
    {
        public LAN8651Control()
        {
            IRQ = new GPIO();
            Reset();
        }

        public GPIO IRQ { get; }
        public uint Revision { get; set; } = 1;

        public void Reset()
        {
            selected = false;
            resetting = false;
            ResetRegisters();
        }

        public void OnGPIO(int number, bool value)
        {
            if(number == 0)
            {
                if(!value && !selected)
                {
                    length = 0;
                    selected = true;
                }
                else if(value && selected)
                {
                    FinishTransmission();
                    selected = false;
                }
                return;
            }
            if(number == 1)
            {
                resetting = !value;
                if(value)
                {
                    ResetRegisters();
                }
                else
                {
                    IRQ.Set();
                }
            }
        }

        public byte Transmit(byte value)
        {
            if(!selected || resetting)
            {
                return 0xff;
            }
            if(length == input.Length)
            {
                valid = false;
                return 0xff;
            }
            int index = length++;
            input[index] = value;
            if(index == 3)
            {
                BeginTransaction();
            }
            if(dataPoll)
            {
                if(index < 64)
                {
                    return 0;
                }
                uint footer = (status == 0 ? 0u : Data) | (valid ? 0u : HeaderBad) | EmptyTransmitCredits;
                return WordByte(footer | (OddParity(footer) ? 0u : 1u), index - 64);
            }
            if(index < 4)
            {
                return 0;
            }
            if(index < 8)
            {
                return WordByte(valid ? header : header | HeaderBad, index - 4);
            }
            uint response = isWrite ? ReadWord(4) : ReadRegister();
            return index < 12 ? WordByte(response, index - 8) : WordByte(~response, index - 12);
        }

        public void FinishTransmission()
        {
            if(length == 0)
            {
                return;
            }
            int expectedLength = dataPoll ? 68 : (protectedMode ? 16 : 12);
            if(!valid || length != expectedLength)
            {
                status |= HeaderError;
                UpdateIRQ();
                this.Log(LogLevel.Warning, "Rejected unsupported or malformed TC6 control transaction");
                length = 0;
                return;
            }
            if(dataPoll)
            {
                interruptPending = false;
                UpdateIRQ();
                length = 0;
                return;
            }
            if(isWrite)
            {
                uint data = ReadWord(4);
                if(protectedMode && ReadWord(8) != ~data)
                {
                    status |= HeaderError;
                    UpdateIRQ();
                    this.Log(LogLevel.Warning, "Rejected TC6 write with bad complement");
                }
                else
                {
                    WriteRegister(data);
                }
            }
            length = 0;
        }

        private void BeginTransaction()
        {
            header = ReadWord(0);
            dataPoll = (header & Data) != 0;
            address = (header >> 8) & 0xfffff;
            isWrite = (header & Write) != 0;
            protectedMode = (config & Protect) != 0;
            valid = OddParity(header) &&
                (dataPoll ? (header & ~1u) == (Data | NoReceive) : (header & (HeaderBad | 0xfe)) == 0);
        }

        private uint ReadRegister()
        {
            switch(address)
            {
                case 0: return 0x11; // OA_IDVER
                case 3: return 0; // OA_RESET is self-clearing.
                case 4: return config;
                case 8: return status;
                case 0xa0094: return 0x86510 | (Revision & 0xf);
                default: return 0;
            }
        }

        private void WriteRegister(uint value)
        {
            switch(address)
            {
                case 3:
                    if((value & 1) != 0)
                    {
                        ResetRegisters();
                    }
                    break;
                case 4:
                    config = value;
                    break;
                case 8:
                    status &= ~value;
                    UpdateIRQ();
                    break;
                default:
                    this.Log(LogLevel.Warning, "Ignored write to unmodeled TC6 register 0x{0:X}", address);
                    break;
            }
        }

        private void ResetRegisters()
        {
            length = 0;
            valid = false;
            config = 6; // Default 64-byte payload size and unprotected control transactions.
            status = ResetComplete;
            interruptPending = true;
            UpdateIRQ();
        }

        private void UpdateIRQ()
        {
            IRQ.Set(status == 0 && !interruptPending);
        }

        private uint ReadWord(int index)
        {
            return (uint)input[index] << 24 | (uint)input[index + 1] << 16 |
                   (uint)input[index + 2] << 8 | input[index + 3];
        }

        private static byte WordByte(uint word, int index)
        {
            return (byte)(word >> (24 - 8 * index));
        }

        private static bool OddParity(uint word)
        {
            word ^= word >> 16;
            word ^= word >> 8;
            word ^= word >> 4;
            word ^= word >> 2;
            word ^= word >> 1;
            return (word & 1) != 0;
        }

        private readonly byte[] input = new byte[68];
        private uint header;
        private uint address;
        private uint config;
        private uint status;
        private int length;
        private bool selected;
        private bool resetting;
        private bool isWrite;
        private bool dataPoll;
        private bool interruptPending;
        private bool valid;
        private bool protectedMode;

        private const uint HeaderBad = 1u << 30;
        private const uint Data = 1u << 31;
        private const uint NoReceive = 1u << 29;
        private const uint Write = 1u << 29;
        private const uint ResetComplete = 1u << 6;
        private const uint HeaderError = 1u << 5;
        private const uint Protect = 1u << 5;
        // The empty transmit buffer advertises at least 31 credits in the TC6 footer.
        private const uint EmptyTransmitCredits = 31u << 1;
    }
}
