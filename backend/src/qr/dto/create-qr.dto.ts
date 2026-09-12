import {
  IsBoolean,
  IsEthereumAddress,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsPositive,
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
}
