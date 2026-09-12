import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import {
  getAddress,
  keccak256,
  parseUnits,
  toEventSelector,
  toFunctionSelector,
  toHex,
} from "viem";

chai.use(chaiAsPromised);

const tUSDT = (n: string) => parseUnits(n, 6);

/// A sale id is `cashier (20 bytes) || 12 random bytes`: the contract reads the
/// cashier straight out of it, so every test that pays has to build one for a
/// registered cashier. The tail is derived from a label just to keep the tests
/// deterministic.
function saleFor(cashier: string, label: string): `0x${string}` {
  const tail = keccak256(toHex(label)).slice(2, 26); // 12 bytes
  return `0x${cashier.slice(2).toLowerCase()}${tail}` as `0x${string}`;
}

async function deployFixture() {
  const [deployer, duenio, pagador, extra] = await hre.viem.getWalletClients();
  const usdt = await hre.viem.deployContract("TestUSDT");
  const router = await hre.viem.deployContract("WalikiRouter", [usdt.address]);
  const publicClient = await hre.viem.getPublicClient();
  return { usdt, router, deployer, duenio, pagador, extra, publicClient };
}

/// Registers a shop owned by `duenio` and funds `pagador` with 100 tUSDT
/// already approved to the router, which is what most tests need.
async function shopFixture() {
  const base = await loadFixture(deployFixture);
  const { usdt, router, duenio, pagador } = base;
  await router.write.registerMerchant([duenio.account.address, "Tienda"], {
    account: duenio.account,
  });
  await usdt.write.faucet({ account: pagador.account });
  await usdt.write.approve([router.address, tUSDT("100")], { account: pagador.account });
  return base;
}

describe("TestUSDT", function () {
  it("tiene 6 decimales y suministro inicial para el kit demo", async function () {
    const { usdt, deployer } = await loadFixture(deployFixture);
    expect(await usdt.read.decimals()).to.equal(6);
    expect(await usdt.read.balanceOf([deployer.account.address])).to.equal(tUSDT("10000"));
  });

  it("el faucet entrega 100 tUSDT y respeta el cooldown", async function () {
    const { usdt, pagador } = await loadFixture(deployFixture);

    await usdt.write.faucet({ account: pagador.account });
    expect(await usdt.read.balanceOf([pagador.account.address])).to.equal(tUSDT("100"));

    await expect(usdt.write.faucet({ account: pagador.account })).to.be.rejectedWith(
      "faucet en cooldown"
    );

    await time.increase(60 * 60); // advance 1 hour
    await usdt.write.faucet({ account: pagador.account });
    expect(await usdt.read.balanceOf([pagador.account.address])).to.equal(tUSDT("200"));
  });
});

describe("WalikiRouter", function () {
  it("registra un comercio con su dirección de cobro y emite el evento", async function () {
    const { router, duenio } = await loadFixture(deployFixture);

    await router.write.registerMerchant([duenio.account.address, "Tienda Demo CBBA"], {
      account: duenio.account,
    });

    expect(await router.read.merchantCount()).to.equal(1n);
    const [owner, payout, name] = await router.read.merchants([1n]);
    expect(getAddress(owner)).to.equal(getAddress(duenio.account.address));
    expect(getAddress(payout)).to.equal(getAddress(duenio.account.address));
    expect(name).to.equal("Tienda Demo CBBA");

    const eventos = await router.getEvents.MerchantRegistered();
    expect(eventos).to.have.lengthOf(1);
    expect(eventos[0].args.merchantId).to.equal(1n);
  });

  it("el dueño queda de alta como cajero de su propio comercio", async function () {
    const { router, duenio, extra } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Tienda"], {
      account: duenio.account,
    });

    expect(await router.read.isCashier([1n, duenio.account.address])).to.equal(true);
    expect(await router.read.isCashier([1n, extra.account.address])).to.equal(false);

    // ...and it shows up in the log, so the owner screen can list itself
    const eventos = await router.getEvents.CashierAdded();
    expect(eventos).to.have.lengthOf(1);
    expect(getAddress(eventos[0].args.cashier!)).to.equal(getAddress(duenio.account.address));
  });

  it("candado: solo el dueño puede cambiar la dirección de cobro", async function () {
    const { router, duenio, pagador, extra } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Tienda"], {
      account: duenio.account,
    });

    // An employee (or any other account) cannot divert the payments
    await expect(
      router.write.setPayoutAddress([1n, pagador.account.address], { account: pagador.account })
    ).to.be.rejectedWith("solo el dueno");

    // The owner can
    await router.write.setPayoutAddress([1n, extra.account.address], { account: duenio.account });
    const [, payout] = await router.read.merchants([1n]);
    expect(getAddress(payout)).to.equal(getAddress(extra.account.address));
  });

  it("pay(): los tUSDT viajan directo del pagador al comercio y se emite PaymentReceived", async function () {
    const { usdt, router, duenio, pagador } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Hamburguesas El Verde"], {
      account: duenio.account,
    });

    const venta = saleFor(duenio.account.address, "venta-demo-001");
    const monto = tUSDT("12.5"); // Bs 175 at 14.00 Bs/USDT
    await usdt.write.faucet({ account: pagador.account });
    await usdt.write.approve([router.address, monto], { account: pagador.account });
    await router.write.pay([1n, venta, monto], { account: pagador.account });

    // Money: payer -> owner, no stopover in the router (non-custodial)
    expect(await usdt.read.balanceOf([pagador.account.address])).to.equal(tUSDT("87.5"));
    expect(await usdt.read.balanceOf([duenio.account.address])).to.equal(monto);
    expect(await usdt.read.balanceOf([router.address])).to.equal(0n);

    // The sale is marked paid (the green screen is driven by the event)
    expect(await router.read.paidAmount([1n, venta])).to.equal(monto);
    const eventos = await router.getEvents.PaymentReceived();
    expect(eventos).to.have.lengthOf(1);
    expect(eventos[0].args.merchantId).to.equal(1n);
    expect(eventos[0].args.saleId).to.equal(venta);
    expect(getAddress(eventos[0].args.payer!)).to.equal(getAddress(pagador.account.address));
    expect(eventos[0].args.amount).to.equal(monto);

    // The attribution travels inside the sale id, nowhere else
    expect(getAddress(await router.read.cashierOf([venta]))).to.equal(
      getAddress(duenio.account.address)
    );
  });

  it("rechaza pagar dos veces la misma venta", async function () {
    const { router, duenio, pagador } = await shopFixture();
    const venta = saleFor(duenio.account.address, "venta-demo-002");

    await router.write.pay([1n, venta, tUSDT("10")], { account: pagador.account });
    await expect(
      router.write.pay([1n, venta, tUSDT("10")], { account: pagador.account })
    ).to.be.rejectedWith("venta ya pagada");
  });

  it("rechaza comercio inexistente, monto cero y pago sin approve", async function () {
    const { usdt, router, duenio, pagador } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Tienda"], {
      account: duenio.account,
    });
    const venta = saleFor(duenio.account.address, "venta-demo-001");

    await expect(
      router.write.pay([99n, venta, tUSDT("1")], { account: pagador.account })
    ).to.be.rejectedWith("comercio inexistente");

    await expect(
      router.write.pay([1n, venta, 0n], { account: pagador.account })
    ).to.be.rejectedWith("monto cero");

    await usdt.write.faucet({ account: pagador.account });
    // Without approve: real USDT also requires the 2 transactions (approve + pay)
    await expect(router.write.pay([1n, venta, tUSDT("1")], { account: pagador.account })).to.be
      .rejected;
  });

  describe("cajeros", function () {
    it("solo el dueño da de alta y de baja", async function () {
      const { router, duenio, pagador, extra } = await shopFixture();

      await expect(
        router.write.addCashier([1n, extra.account.address, "Caja 1"], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("solo el dueno");

      await router.write.addCashier([1n, extra.account.address, "Caja 1"], {
        account: duenio.account,
      });
      expect(await router.read.isCashier([1n, extra.account.address])).to.equal(true);

      await expect(
        router.write.removeCashier([1n, extra.account.address], { account: pagador.account })
      ).to.be.rejectedWith("solo el dueno");

      await router.write.removeCashier([1n, extra.account.address], { account: duenio.account });
      expect(await router.read.isCashier([1n, extra.account.address])).to.equal(false);
    });

    it("la etiqueta viaja en el evento, no en el storage", async function () {
      const { router, duenio, extra } = await shopFixture();
      await router.write.addCashier([1n, extra.account.address, "Mostrador"], {
        account: duenio.account,
      });

      const eventos = await router.getEvents.CashierAdded();
      const ultimo = eventos[eventos.length - 1];
      expect(ultimo.args.label).to.equal("Mostrador");
      expect(getAddress(ultimo.args.cashier!)).to.equal(getAddress(extra.account.address));
    });

    it("una venta del cajero se cobra y queda atribuida a él", async function () {
      const { usdt, router, duenio, pagador, extra } = await shopFixture();
      await router.write.addCashier([1n, extra.account.address, "Caja 1"], {
        account: duenio.account,
      });

      const venta = saleFor(extra.account.address, "venta-del-cajero");
      await router.write.pay([1n, venta, tUSDT("7")], { account: pagador.account });

      // The money still goes to the shop, never to the cashier
      expect(await usdt.read.balanceOf([duenio.account.address])).to.equal(tUSDT("7"));
      expect(await usdt.read.balanceOf([extra.account.address])).to.equal(0n);
      expect(getAddress(await router.read.cashierOf([venta]))).to.equal(
        getAddress(extra.account.address)
      );
    });

    it("un cajero dado de baja ya no puede cobrar", async function () {
      const { router, duenio, pagador, extra } = await shopFixture();
      await router.write.addCashier([1n, extra.account.address, "Caja 1"], {
        account: duenio.account,
      });

      // A sale of theirs that nobody paid yet...
      const pendiente = saleFor(extra.account.address, "venta-en-vuelo");
      await router.write.removeCashier([1n, extra.account.address], { account: duenio.account });

      // ...stops being payable the moment the owner revokes them
      await expect(
        router.write.pay([1n, pendiente, tUSDT("5")], { account: pagador.account })
      ).to.be.rejectedWith("cajero no autorizado");

      // and the owner keeps charging as usual
      await router.write.pay([1n, saleFor(duenio.account.address, "venta-del-dueno"), tUSDT("5")], {
        account: pagador.account,
      });
    });

    it("una venta con el prefijo de una dirección cualquiera se rechaza", async function () {
      const { router, pagador, extra } = await shopFixture();

      // extra was never added as a cashier of shop #1
      await expect(
        router.write.pay([1n, saleFor(extra.account.address, "x"), tUSDT("1")], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("cajero no autorizado");

      // ...and neither is a purely random sale id, which is what the old
      // cash registers used to generate
      await expect(
        router.write.pay([1n, keccak256(toHex("venta-sin-cajero")), tUSDT("1")], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("cajero no autorizado");
    });

    it("los cajeros de un comercio no cobran en otro", async function () {
      const { router, duenio, pagador, extra } = await shopFixture();
      // Shop #2, owned by someone else
      await router.write.registerMerchant([pagador.account.address, "Otra tienda"], {
        account: pagador.account,
      });
      await router.write.addCashier([1n, extra.account.address, "Caja 1"], {
        account: duenio.account,
      });

      expect(await router.read.isCashier([1n, extra.account.address])).to.equal(true);
      expect(await router.read.isCashier([2n, extra.account.address])).to.equal(false);

      await expect(
        router.write.pay([2n, saleFor(extra.account.address, "y"), tUSDT("1")], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("cajero no autorizado");
    });

    it("alta, baja y alta otra vez de la misma dirección", async function () {
      const { router, duenio, pagador, extra, publicClient } = await shopFixture();
      const cajero = extra.account.address;

      await router.write.addCashier([1n, cajero, "Caja 1"], { account: duenio.account });
      await router.write.removeCashier([1n, cajero], { account: duenio.account });
      await router.write.addCashier([1n, cajero, "Caja 1 (de nuevo)"], { account: duenio.account });

      expect(await router.read.isCashier([1n, cajero])).to.equal(true);
      await router.write.pay([1n, saleFor(cajero, "z"), tUSDT("3")], { account: pagador.account });

      // The log alone reads alta-baja-alta (plus the owner's own alta): replayed
      // out of order it says the wrong thing, which is why the app confirms
      // every address it rebuilds from the events against isCashier.
      const altas = await publicClient.getContractEvents({
        address: router.address,
        abi: router.abi,
        eventName: "CashierAdded",
        fromBlock: 0n,
      });
      const bajas = await publicClient.getContractEvents({
        address: router.address,
        abi: router.abi,
        eventName: "CashierRemoved",
        fromBlock: 0n,
      });
      expect(altas).to.have.lengthOf(3); // el dueno + las dos altas del cajero
      expect(bajas).to.have.lengthOf(1);
    });

    it("no se puede dar de baja al dueño ni a quien no es cajero", async function () {
      const { router, duenio, extra } = await shopFixture();

      await expect(
        router.write.removeCashier([1n, duenio.account.address], { account: duenio.account })
      ).to.be.rejectedWith("el dueno no se puede quitar");

      await expect(
        router.write.removeCashier([1n, extra.account.address], { account: duenio.account })
      ).to.be.rejectedWith("no es cajero");
    });
  });

  describe("traspaso del comercio", function () {
    it("va en dos pasos y solo lo completa el dueño propuesto", async function () {
      const { router, duenio, pagador, extra } = await shopFixture();

      await expect(
        router.write.transferMerchantOwnership([1n, extra.account.address], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("solo el dueno");

      await router.write.transferMerchantOwnership([1n, extra.account.address], {
        account: duenio.account,
      });

      // Nothing has changed yet: a typo is still recoverable
      const [ownerAntes] = await router.read.merchants([1n]);
      expect(getAddress(ownerAntes)).to.equal(getAddress(duenio.account.address));
      expect(getAddress(await router.read.pendingOwner([1n]))).to.equal(
        getAddress(extra.account.address)
      );

      await expect(
        router.write.acceptMerchantOwnership([1n], { account: pagador.account })
      ).to.be.rejectedWith("no eres el dueno propuesto");

      await router.write.acceptMerchantOwnership([1n], { account: extra.account });
      const [ownerDespues] = await router.read.merchants([1n]);
      expect(getAddress(ownerDespues)).to.equal(getAddress(extra.account.address));
      expect(await router.read.pendingOwner([1n])).to.equal(
        "0x0000000000000000000000000000000000000000"
      );
      expect(await router.read.isCashier([1n, extra.account.address])).to.equal(true);
    });

    it("el dueño anterior sigue cobrando las ventas que tenía en pantalla", async function () {
      const { router, duenio, pagador, extra } = await shopFixture();
      const enVuelo = saleFor(duenio.account.address, "venta-en-la-pantalla");

      await router.write.transferMerchantOwnership([1n, extra.account.address], {
        account: duenio.account,
      });
      await router.write.acceptMerchantOwnership([1n], { account: extra.account });

      // The sale survives the handover...
      await router.write.pay([1n, enVuelo, tUSDT("4")], { account: pagador.account });

      // ...and then the new owner can cut the previous one off
      await router.write.removeCashier([1n, duenio.account.address], { account: extra.account });
      await expect(
        router.write.pay([1n, saleFor(duenio.account.address, "otra"), tUSDT("4")], {
          account: pagador.account,
        })
      ).to.be.rejectedWith("cajero no autorizado");
    });

    it("el dueño puede cancelar un traspaso pendiente", async function () {
      const { router, duenio, extra } = await shopFixture();

      await expect(
        router.write.cancelMerchantOwnershipTransfer([1n], { account: duenio.account })
      ).to.be.rejectedWith("no hay traspaso pendiente");

      await router.write.transferMerchantOwnership([1n, extra.account.address], {
        account: duenio.account,
      });
      await router.write.cancelMerchantOwnershipTransfer([1n], { account: duenio.account });

      await expect(
        router.write.acceptMerchantOwnership([1n], { account: extra.account })
      ).to.be.rejectedWith("no eres el dueno propuesto");
    });
  });

  // The Flutter app has no ABI: it builds calldata by hand and filters
  // eth_getLogs with these hexes written into chain.dart and wallet.dart.
  // Renaming a function or reordering a parameter changes them, and the app
  // fails SILENTLY -- an empty history, a payment that never turns green.
  // This test is the only thing standing between that and a release.
  describe("regresión de selectores y topic0 (los lleva la app escritos a mano)", function () {
    const FUNCIONES: Record<string, `0x${string}`> = {
      "registerMerchant(address,string)": "0xa6c8a384",
      "setPayoutAddress(uint256,address)": "0xdfefa227",
      "pay(uint256,bytes32,uint256)": "0x3fcf3bfe",
      "paidAmount(uint256,bytes32)": "0x9378fd0b",
      "merchants(uint256)": "0x92c8823b",
      "merchantCount()": "0x89105185",
      "isCashier(uint256,address)": "0x909cf575",
      "cashierOf(bytes32)": "0xab515d2c",
      "addCashier(uint256,address,string)": "0x7961ffdc",
      "removeCashier(uint256,address)": "0xed164620",
      "pendingOwner(uint256)": "0x2b800e3b",
      "transferMerchantOwnership(uint256,address)": "0x27146d6c",
      "acceptMerchantOwnership(uint256)": "0x54f83d86",
      "cancelMerchantOwnershipTransfer(uint256)": "0x2c77a635",
    };

    const EVENTOS: Record<string, `0x${string}`> = {
      "MerchantRegistered(uint256,address,address,string)":
        "0x037fddc1b3113ac1da8bedf43384dd2830a0409fdb349f3cd03c79f9c0a09dbc",
      "PaymentReceived(uint256,bytes32,address,uint256,address)":
        "0x0b385fcca75fcb7ea5db933cc6da0cc478e6a99e11d3596eedb8fde3897caff7",
      "CashierAdded(uint256,address,string)":
        "0xe3343999af5709fd77744d1e75d1f52604472c522e29a62cde2e4e284cba55ec",
      "CashierRemoved(uint256,address)":
        "0x54a78a91dea4745892ac90c82e3b81b4bbff52f2d6bececff18bff4fc2608fc7",
    };

    /// Signatures the compiled ABI actually declares. Comparing against these
    /// is what ties the literals above to the contract: a reordered parameter
    /// makes the signature disappear from this set.
    async function firmasDelAbi(tipo: "function" | "event"): Promise<Set<string>> {
      const artifact = await hre.artifacts.readArtifact("WalikiRouter");
      return new Set(
        artifact.abi
          .filter((e: any) => e.type === tipo)
          .map((e: any) => `${e.name}(${e.inputs.map((i: any) => i.type).join(",")})`)
      );
    }

    it("el contrato declara exactamente estas firmas de función", async function () {
      const firmas = await firmasDelAbi("function");
      for (const firma of Object.keys(FUNCIONES)) {
        expect(firmas.has(firma), `el contrato ya no declara ${firma}`).to.equal(true);
      }
    });

    it("cada selector coincide con el keccak de su firma", async function () {
      for (const [firma, selector] of Object.entries(FUNCIONES)) {
        expect(toFunctionSelector(`function ${firma}`), firma).to.equal(selector);
      }
    });

    it("el contrato declara exactamente estos eventos y sus topic0 no se movieron", async function () {
      const firmas = await firmasDelAbi("event");
      for (const [firma, topic0] of Object.entries(EVENTOS)) {
        expect(firmas.has(firma), `el contrato ya no emite ${firma}`).to.equal(true);
        expect(toEventSelector(`event ${firma}`), firma).to.equal(topic0);
      }
    });
  });
});
