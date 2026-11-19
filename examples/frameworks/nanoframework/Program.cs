using System.Diagnostics;
using System.Threading;

namespace UniClickerHello
{
    public static class Program
    {
        public static void Main()
        {
            while (true)
            {
                Debug.WriteLine("Hello, UNI Clicker from .NET nanoFramework!");
                Thread.Sleep(1000);
            }
        }
    }
}
