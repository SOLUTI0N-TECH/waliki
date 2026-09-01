import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { getAddress, keccak256, parseUnits, toHex } from "viem";

chai.use(chaiAsPromised);

const tUSDT = (n: string) => parseUnits(n, 6);
const SALE_1 = keccak256(toHex("venta-demo-001"));
const SALE_2 = keccak256(toHex("venta-demo-002"));

async function deployFixture() {
  const [deployer, duenio, pagador, extra] = await hre.viem.getWalletClients();
  const usdt = await hre.viem.deployContract("TestUSDT");
  const router = await hre.viem.deployContract("WalikiRouter", [usdt.address]);
  const publicClient = await hre.viem.getPublicClient();
  return { usdt, router, deployer, duenio, pagador, extra, publicClient };
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

    const monto = tUSDT("12.5"); // Bs 175 at 14.00 Bs/USDT
    await usdt.write.faucet({ account: pagador.account });
    await usdt.write.approve([router.address, monto], { account: pagador.account });
    await router.write.pay([1n, SALE_1, monto], { account: pagador.account });

    // Money: payer -> owner, no stopover in the router (non-custodial)
    expect(await usdt.read.balanceOf([pagador.account.address])).to.equal(tUSDT("87.5"));
    expect(await usdt.read.balanceOf([duenio.account.address])).to.equal(monto);
    expect(await usdt.read.balanceOf([router.address])).to.equal(0n);

    // The sale is marked paid (the green screen is driven by the event)
    expect(await router.read.paidAmount([1n, SALE_1])).to.equal(monto);
    const eventos = await router.getEvents.PaymentReceived();
    expect(eventos).to.have.lengthOf(1);
    expect(eventos[0].args.merchantId).to.equal(1n);
    expect(eventos[0].args.saleId).to.equal(SALE_1);
    expect(getAddress(eventos[0].args.payer!)).to.equal(getAddress(pagador.account.address));
    expect(eventos[0].args.amount).to.equal(monto);
  });

  it("rechaza pagar dos veces la misma venta", async function () {
    const { usdt, router, duenio, pagador } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Tienda"], {
      account: duenio.account,
    });
    await usdt.write.faucet({ account: pagador.account });
    await usdt.write.approve([router.address, tUSDT("100")], { account: pagador.account });

    await router.write.pay([1n, SALE_2, tUSDT("10")], { account: pagador.account });
    await expect(
      router.write.pay([1n, SALE_2, tUSDT("10")], { account: pagador.account })
    ).to.be.rejectedWith("venta ya pagada");
  });

  it("rechaza comercio inexistente, monto cero y pago sin approve", async function () {
    const { usdt, router, duenio, pagador } = await loadFixture(deployFixture);
    await router.write.registerMerchant([duenio.account.address, "Tienda"], {
      account: duenio.account,
    });

    await expect(
      router.write.pay([99n, SALE_1, tUSDT("1")], { account: pagador.account })
    ).to.be.rejectedWith("comercio inexistente");

    await expect(
      router.write.pay([1n, SALE_1, 0n], { account: pagador.account })
    ).to.be.rejectedWith("monto cero");

    await usdt.write.faucet({ account: pagador.account });
    // Without approve: real USDT also requires the 2 transactions (approve + pay)
    await expect(router.write.pay([1n, SALE_1, tUSDT("1")], { account: pagador.account })).to.be
      .rejected;
  });
});
