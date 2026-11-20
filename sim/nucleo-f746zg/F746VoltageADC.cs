using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Exceptions;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Peripherals.Sensor;
using Antmicro.Renode.Peripherals.Timers;
using Antmicro.Renode.Time;
using Antmicro.Renode.Utilities.RESD;

namespace Antmicro.Renode.Peripherals.Analog
{
    // F746 regular conversions with one selected input per ADC and a fixed conversion time.
    [AllowedTranslations(AllowedTranslation.WordToDoubleWord)]
    public class F746VoltageADC : BasicDoubleWordPeripheral, IKnownSize, IADC
    {
        public F746VoltageADC(IMachine machine, decimal referenceVoltage = 3.3m) : base(machine)
        {
            if(referenceVoltage <= 0)
            {
                throw new ConstructionException("ADC reference voltage must be positive");
            }
            this.referenceVoltage = referenceVoltage;
            ADCContainer = new SimpleContainerHelper<IRESDSampleSource<VoltageSample>>(machine, this);
            this.RegisterDefaultChildren(machine);

            conversionTimer = new LimitTimer(machine.ClockSource, 1000000, this, "conversion",
                limit: 100, enabled: false, eventEnabled: true);
            conversionTimer.LimitReached += CompleteConversion;
            DefineRegisters();
        }

        public override void Reset()
        {
            base.Reset();
            conversionTimer.Reset();
            data = 0;
            dmaRequested = false;
            IRQ.Unset();
            DMARequest.Unset();
        }

        public int ADCChannelCount => 19;
        public SimpleContainerHelper<IRESDSampleSource<VoltageSample>> ADCContainer { get; }
        public long Size => 0x50;
        public GPIO IRQ { get; } = new GPIO();
        public GPIO DMARequest { get; } = new GPIO();

        private void DefineRegisters()
        {
            Registers.Status.Define(this)
                .WithFlag(1, out endOfConversion, mode: FieldMode.Read | FieldMode.WriteZeroToClear, name: "EOC")
                .WithChangeCallback((_, __) => UpdateInterrupt());

            Registers.Control1.Define(this)
                .WithFlag(5, out interruptEnabled, name: "EOCIE")
                .WithValueField(24, 2, out resolution, name: "RES")
                .WithChangeCallback((_, __) => UpdateInterrupt());

            Registers.Control2.Define(this)
                .WithFlag(0, out enabled, name: "ADON", changeCallback: (_, value) =>
                {
                    if(!value)
                    {
                        conversionTimer.Enabled = false;
                    }
                })
                .WithFlag(1, out continuous, name: "CONT")
                .WithFlag(8, out dmaEnabled, name: "DMA")
                .WithFlag(9, out dmaContinuous, name: "DDS")
                .WithTaggedFlag("EOCS", 10)
                .WithFlag(11, out leftAligned, name: "ALIGN")
                .WithFlag(30, name: "SWSTART", valueProviderCallback: _ => false, writeCallback: (_, value) =>
                {
                    if(value && enabled.Value && !conversionTimer.Enabled)
                    {
                        dmaRequested = false;
                        conversionTimer.ResetValue();
                        conversionTimer.Enabled = true;
                    }
                });

            Registers.RegularSequence1.Define(this).WithTag("L", 20, 4);
            Registers.RegularSequence3.Define(this).WithValueField(0, 5, out channel, name: "SQ1");
            Registers.RegularData.Define(this)
                .WithValueField(0, 16, FieldMode.Read, name: "DATA", valueProviderCallback: _ =>
                {
                    endOfConversion.Value = false;
                    UpdateInterrupt();
                    return data;
                });
        }

        private void CompleteConversion()
        {
            var bits = (ushort)(12 - 2 * resolution.Value);
            data = ADCContainer.TryGetByAddress((int)channel.Value, out var source)
                ? source.Sample.ToADCRawValue(referenceVoltage, bits)
                : 0;
            if(leftAligned.Value)
            {
                data <<= 16 - bits;
            }

            endOfConversion.Value = true;
            UpdateInterrupt();
            if(dmaEnabled.Value && (dmaContinuous.Value || !dmaRequested))
            {
                dmaRequested = true;
                DMARequest.Blink();
            }
            if(!continuous.Value)
            {
                conversionTimer.Enabled = false;
            }
        }

        private void UpdateInterrupt()
        {
            IRQ.Set(endOfConversion.Value && interruptEnabled.Value);
        }

        private readonly decimal referenceVoltage;
        private readonly LimitTimer conversionTimer;
        private IFlagRegisterField endOfConversion;
        private IFlagRegisterField interruptEnabled;
        private IFlagRegisterField enabled;
        private IFlagRegisterField continuous;
        private IFlagRegisterField dmaEnabled;
        private IFlagRegisterField dmaContinuous;
        private IFlagRegisterField leftAligned;
        private IValueRegisterField resolution;
        private IValueRegisterField channel;
        private uint data;
        private bool dmaRequested;

        private enum Registers
        {
            Status = 0x00,
            Control1 = 0x04,
            Control2 = 0x08,
            RegularSequence1 = 0x2c,
            RegularSequence3 = 0x34,
            RegularData = 0x4c,
        }
    }
}
