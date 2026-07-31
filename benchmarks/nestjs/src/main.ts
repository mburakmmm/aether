import 'reflect-metadata';
import { Body, Controller, Get, Module, Post } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';

class EchoDto {
  msg!: string;
}

@Controller()
class BenchController {
  @Get('ping')
  ping(): { pong: boolean } {
    return { pong: true };
  }

  @Post('echo')
  echo(@Body() body: EchoDto): { msg: string } {
    return { msg: body.msg };
  }
}

@Module({ controllers: [BenchController] })
class AppModule {}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: false });
  const port = Number(process.env.PORT ?? '3002');
  await app.listen(port, '0.0.0.0');
}

bootstrap();
