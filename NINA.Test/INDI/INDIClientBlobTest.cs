#region "copyright"

/*
    Copyright © 2025-2026 Nico Trost <nico.trost57@gmail.com> and the PI.N.S. contributors

    This file is part of PI 'N' Stars.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

using FluentAssertions;
using NINA.INDI;
using NINA.INDI.Devices;
using NINA.INDI.Enums;
using NINA.INDI.Protocol;
using NUnit.Framework;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace NINA.Test.INDI {

    /// <summary>
    /// Camera images are parsed, decoded and applied on a worker, so the property updates behind a
    /// multi-megabyte image on the wire (guide pulses completing, exposure states) are processed
    /// right away. The client runs against a fake indiserver on a loopback port.
    /// </summary>
    [TestFixture]
    [NonParallelizable]
    public class INDIClientBlobTest {
        private const string Camera = "CCD Simulator";
        private const string Mount = "Telescope Simulator";
        private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

        private FakeIndiServer server = null!;
        private INDIClient client = null!;
        [System.Diagnostics.CodeAnalysis.SuppressMessage("Structure", "NUnit1032", Justification = "Borrowed singleton, restored in TearDown")]
        private INDIClient? previousInstance;
        private FakeIndiServer.Connection main = null!;

        [SetUp]
        public async Task SetUp() {
            server = new FakeIndiServer();
            client = new INDIClient(server.Port, startServer: false);
            // INDIDevice talks to INDIClient.Instance
            previousInstance = INDIClient.SetInstanceForTests(client);
            (await client.Connect()).Should().BeTrue();
            main = await server.NextConnectionAsync(Timeout);
        }

        [TearDown]
        public void TearDown() {
            client.Dispose();
            INDIClient.SetInstanceForTests(previousInstance);
            server.Dispose();
        }

        [Test]
        public async Task UpdateBehindAnImage_IsProcessedBeforeTheImageIsApplied() {
            var device = await RegisterCameraAsync();
            main.Send(DefGuideNs());
            await WaitUntilAsync(() => GuideNsState() == "Idle", "the guide property is defined");
            var image = new byte[32 * 1024 * 1024];
            new Random(1).NextBytes(image);

            // A guide pulse completing right behind a large image on the wire
            main.Send(SetBlob(image) + SetGuideNs("Ok"));

            await WaitUntilAsync(() => GuideNsState() == "Ok", "the pulse completion is processed");
            ImageOf(device).Should().BeEmpty("the image is still being parsed and decoded");
            await WaitUntilAsync(() => ImageOf(device)?.Length == image.Length, "the image arrives after all");
            ImageOf(device).Should().Equal(image);
        }

        [Test]
        public async Task Images_AreAppliedInArrivalOrder() {
            var device = await RegisterCameraAsync();
            var first = Enumerable.Repeat((byte)1, 4 * 1024 * 1024).ToArray();
            var second = Enumerable.Repeat((byte)2, 1000).ToArray();

            main.Send(SetBlob(first) + SetBlob(second));

            await WaitUntilAsync(() => ImageOf(device)?.Length == second.Length, "the second image is applied");
            await Task.Delay(200);
            ImageOf(device).Should().Equal(second, "the larger first image must not overwrite it afterwards");
        }

        private async Task<INDIDevice> RegisterCameraAsync() {
            var create = Task.Run(() => new INDIDevice(new INDIDeviceInfo { Id = Camera, Name = Camera, Interface = DeviceInterface.CCD_INTERFACE }));
            // The new device asks for its properties and waits for CONNECTION.
            await main.WaitForAsync($"<getProperties version=\"1.7\" device=\"{Camera}\" />", Timeout);
            main.Send(
                $"<defSwitchVector device=\"{Camera}\" name=\"CONNECTION\" label=\"Connection\" group=\"Main\" state=\"Idle\" perm=\"rw\" rule=\"OneOfMany\" timeout=\"60\">"
                + "<defSwitch name=\"CONNECT\" label=\"Connect\">On</defSwitch><defSwitch name=\"DISCONNECT\" label=\"Disconnect\">Off</defSwitch></defSwitchVector>\n"
                + $"<defBLOBVector device=\"{Camera}\" name=\"CCD1\" label=\"Image\" group=\"Image\" state=\"Idle\" perm=\"ro\" timeout=\"60\"><defBLOB name=\"CCD1\" label=\"Image\"/></defBLOBVector>\n");
            (await Task.WhenAny(create, Task.Delay(Timeout))).Should().Be(create, "the device registers");
            return await create;
        }

        private static byte[]? ImageOf(INDIDevice device) {
            return (device.GetProperty("CCD1") as INDIBlobProperty)?.Blobs.FirstOrDefault()?.Data;
        }

        private string? GuideNsState() {
            return client.GetDeviceSnapshots(Mount)
                .SelectMany(d => d.Properties)
                .FirstOrDefault(p => p.Name == "TELESCOPE_TIMED_GUIDE_NS")?.State;
        }

        private static string SetBlob(byte[] data) {
            // libindi wraps the base64 payload in lines
            var base64 = Convert.ToBase64String(data, Base64FormattingOptions.InsertLineBreaks);
            return $"<setBLOBVector device=\"{Camera}\" name=\"CCD1\" state=\"Ok\" timeout=\"60\">"
                + $"<oneBLOB name=\"CCD1\" size=\"{data.Length}\" enclen=\"{base64.Length}\" format=\".fits\">\n{base64}\n</oneBLOB></setBLOBVector>\n";
        }

        private static string DefGuideNs() {
            return $"<defNumberVector device=\"{Mount}\" name=\"TELESCOPE_TIMED_GUIDE_NS\" label=\"Guide N/S\" group=\"Guide\" state=\"Idle\" perm=\"rw\" timeout=\"0\">"
                + "<defNumber name=\"TIMED_GUIDE_N\" label=\"North\" format=\"%.f\" min=\"0\" max=\"60000\" step=\"100\">0</defNumber>"
                + "<defNumber name=\"TIMED_GUIDE_S\" label=\"South\" format=\"%.f\" min=\"0\" max=\"60000\" step=\"100\">0</defNumber></defNumberVector>\n";
        }

        private static string SetGuideNs(string state) {
            return $"<setNumberVector device=\"{Mount}\" name=\"TELESCOPE_TIMED_GUIDE_NS\" state=\"{state}\" timeout=\"0\">"
                + "<oneNumber name=\"TIMED_GUIDE_N\">0</oneNumber><oneNumber name=\"TIMED_GUIDE_S\">0</oneNumber></setNumberVector>\n";
        }

        private static async Task WaitUntilAsync(Func<bool> condition, string because) {
            var deadline = DateTime.UtcNow + Timeout;
            while (!condition()) {
                if (DateTime.UtcNow > deadline) {
                    Assert.Fail($"Timed out waiting until {because}");
                }
                await Task.Delay(10);
            }
        }
    }

    [TestFixture]
    public class INDIProtocolParserBlobTest {

        [Test]
        public void UpdateBlobProperty_InflatesZlibPayloads() {
            var image = Enumerable.Range(0, 5000).Select(i => (byte)(i % 7)).ToArray();
            var compressed = new System.IO.MemoryStream();
            using (var zlib = new System.IO.Compression.ZLibStream(compressed, System.IO.Compression.CompressionLevel.Optimal, leaveOpen: true)) {
                zlib.Write(image);
            }
            var prop = new INDIBlobProperty { Name = "CCD1" };

            INDIProtocolParser.UpdateBlobProperty(prop, SetBlob(Convert.ToBase64String(compressed.ToArray()), ".fits.z", "Ok"));

            prop.State.Should().Be(PropertyState.Ok);
            prop.Blobs.Should().ContainSingle();
            prop.Blobs[0].Format.Should().Be(".fits");
            prop.Blobs[0].Data.Should().Equal(image);
        }

        [Test]
        public void UpdateBlobProperty_InvalidPayload_EmptiesTheData() {
            var prop = new INDIBlobProperty { Name = "CCD1" };
            prop.Blobs.Add(new INDIBlob { Name = "CCD1", Data = [1, 2, 3] });

            INDIProtocolParser.UpdateBlobProperty(prop, SetBlob("not base64!", ".fits", "Ok"));

            prop.Blobs[0].Data.Should().BeEmpty();
            prop.Blobs[0].Format.Should().Be(".fits");
        }

        [Test]
        public void UpdateBlobProperty_EmptyPayload_KeepsTheData() {
            var prop = new INDIBlobProperty { Name = "CCD1" };
            prop.Blobs.Add(new INDIBlob { Name = "CCD1", Format = ".fits", Data = [1, 2, 3] });

            INDIProtocolParser.UpdateBlobProperty(prop, SetBlob("", ".xisf", "Busy"));

            prop.State.Should().Be(PropertyState.Busy);
            prop.Blobs[0].Data.Should().Equal(1, 2, 3);
            prop.Blobs[0].Format.Should().Be(".xisf");
        }

        private static System.Xml.Linq.XElement SetBlob(string payload, string format, string state) {
            return System.Xml.Linq.XElement.Parse(
                $"<setBLOBVector device=\"Cam\" name=\"CCD1\" state=\"{state}\"><oneBLOB name=\"CCD1\" format=\"{format}\">{payload}</oneBLOB></setBLOBVector>");
        }
    }

    /// <summary>Loopback stand-in for indiserver: accepts connections, records what the client sends and sends raw XML.</summary>
    internal sealed class FakeIndiServer : IDisposable {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        private readonly Channel<Connection> accepted = Channel.CreateUnbounded<Connection>();
        private readonly List<Connection> connections = [];
        private readonly CancellationTokenSource cts = new();

        public FakeIndiServer() {
            listener.Start();
            Port = ((IPEndPoint)listener.LocalEndpoint).Port;
            _ = AcceptLoopAsync();
        }

        public int Port { get; }

        private async Task AcceptLoopAsync() {
            try {
                while (true) {
                    var connection = new Connection(await listener.AcceptTcpClientAsync(cts.Token));
                    lock (connections) {
                        connections.Add(connection);
                    }
                    accepted.Writer.TryWrite(connection);
                }
            } catch (Exception) {
                // stopped
            }
        }

        public async Task<Connection> NextConnectionAsync(TimeSpan timeout) {
            using var timeoutCts = new CancellationTokenSource(timeout);
            return await accepted.Reader.ReadAsync(timeoutCts.Token);
        }

        public void Dispose() {
            cts.Cancel();
            listener.Stop();
            lock (connections) {
                foreach (var connection in connections) {
                    connection.Close();
                }
            }
        }

        internal sealed class Connection {
            private readonly TcpClient tcp;
            private readonly NetworkStream stream;
            private readonly StringBuilder received = new();

            public Connection(TcpClient tcp) {
                this.tcp = tcp;
                stream = tcp.GetStream();
                _ = ReadLoopAsync();
            }

            public string Received {
                get {
                    lock (received) {
                        return received.ToString();
                    }
                }
            }

            private async Task ReadLoopAsync() {
                var buffer = new byte[65536];
                try {
                    int n;
                    while ((n = await stream.ReadAsync(buffer)) > 0) {
                        lock (received) {
                            received.Append(Encoding.UTF8.GetString(buffer, 0, n));
                        }
                    }
                } catch (Exception) {
                    // closed
                }
            }

            public void Send(string xml) {
                var bytes = Encoding.UTF8.GetBytes(xml);
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }

            public async Task WaitForAsync(string text, TimeSpan timeout) {
                var deadline = DateTime.UtcNow + timeout;
                while (!Received.Contains(text)) {
                    if (DateTime.UtcNow > deadline) {
                        Assert.Fail($"Timed out waiting for {text}; received: {Received}");
                    }
                    await Task.Delay(10);
                }
            }

            public void Close() {
                tcp.Close();
            }
        }
    }
}
