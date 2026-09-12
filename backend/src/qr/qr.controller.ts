import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { CreateQrDto } from './dto/create-qr.dto';
import { QrService } from './qr.service';
import type { QrResponse } from './qr.types';

@Controller('qr')
export class QrController {
  constructor(private readonly qr: QrService) {}

  @Post()
  create(@Body() dto: CreateQrDto): Promise<QrResponse> {
    return this.qr.create(dto);
  }

  @Get(':id/status')
  status(@Param('id') id: string): Promise<QrResponse> {
    return this.qr.status(id);
  }
}
