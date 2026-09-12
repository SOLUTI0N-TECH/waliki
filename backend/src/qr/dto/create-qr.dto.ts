import {
  IsBoolean,
  IsEthereumAddress,
  IsISO8601,
  IsNumber,
  IsInt,
  IsOptional,
  IsPositive,
  Matches,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';

export class CreateQrDto {
  /// Fiat amount in Bs. Omitted (or zero) means an open-amount QR.
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  amount?: number;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  additionalData?: string;

  @IsOptional()
  @IsBoolean()
  singleUse?: boolean;

  /// Kept as a string: the body carries ISO text, not a Date instance.
  @IsOptional()
  @IsISO8601({ strict: true })
  expiresAt?: string;

  /// tUSDT released to destinationWallet once the QR is paid.
  @IsNumber({ maxDecimalPlaces: 6 })
  @IsPositive()
  cryptoAmount!: number;

  /// Checked again with ethers before signing: this decorator does not
  /// validate the EIP-55 checksum, only the shape.
  @IsEthereumAddress()
  destinationWallet!: string;

  /// Shop this sale belongs to. With it (and saleId) the settlement goes
  /// through WalikiRouter, so the sale emits PaymentReceived and shows up in
  /// the app's history; without it, it falls back to a plain transfer to
  /// destinationWallet.
  @IsOptional()
  @IsInt()
  @IsPositive()
  merchantId?: number;

  /// bytes32 chosen by the caller. The contract stores it and refuses a second
  /// payment for the same one, which is what makes a retry safe.
  @IsOptional()
  @Matches(/^0x[0-9a-fA-F]{64}$/, {
    message: 'saleId debe ser bytes32 (0x seguido de 64 caracteres hex)',
  })
  saleId?: string;
}
