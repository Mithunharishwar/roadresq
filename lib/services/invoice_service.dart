// FILE: lib/services/invoice_service.dart
/// §45 — build a real PDF invoice and hand it to the system share sheet.
///
/// The figures mirror the pricing model the backend uses (base fare, per-km,
/// service surcharge, GST) but are taken from the job record where available.
/// Anything the record does not carry is printed as "—" rather than guessed.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_constants.dart';

class InvoiceData {
  const InvoiceData({
    required this.requestId,
    required this.customerName,
    required this.customerPhone,
    required this.issue,
    this.vehicle = '',
    this.locationText = '',
    this.amount = 0,
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.mechanicName = '',
    this.assistantName = '',
    this.date,
    this.taxPercent = AppConstants.gstPercent,
    this.commissionPercent = AppConstants.platformCommissionPercent,
  });

  final String requestId;
  final String customerName;
  final String customerPhone;
  final String issue;
  final String vehicle;
  final String locationText;
  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final String mechanicName;
  final String assistantName;
  final DateTime? date;
  final double taxPercent;
  final double commissionPercent;

  /// Amount is treated as tax-inclusive (the figure the customer was quoted),
  /// so the tax portion is extracted rather than added on top.
  double get taxAmount =>
      amount <= 0 ? 0 : amount * taxPercent / (100 + taxPercent);

  double get netAmount => amount - taxAmount;

  double get commission => netAmount * commissionPercent / 100;

  double get crewPayout => netAmount - commission;

  String get invoiceNumber =>
      'RQ-${requestId.length > 8 ? requestId.substring(requestId.length - 8) : requestId}';
}

class InvoiceService {
  InvoiceService._();

  static final NumberFormat _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
  static final DateFormat _stamp = DateFormat('dd MMM yyyy, HH:mm');

  /// Build the PDF bytes. Public so it can be unit-tested without a device.
  static Future<Uint8List> buildPdf(InvoiceData data) async {
    final doc = pw.Document();
    final issued = data.date ?? DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('RoadResQ',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(AppConstants.companyName,
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('support@roadresq.com',
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('No. ${data.invoiceNumber}',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(_stamp.format(issued),
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Billed to',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text(data.customerName.isEmpty ? '—' : data.customerName,
                        style: const pw.TextStyle(fontSize: 10)),
                    if (data.customerPhone.isNotEmpty)
                      pw.Text(data.customerPhone,
                          style: const pw.TextStyle(fontSize: 10)),
                    if (data.locationText.isNotEmpty)
                      pw.Text(data.locationText,
                          style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Job',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text('ID: ${data.requestId}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Issue: ${data.issue}',
                        style: const pw.TextStyle(fontSize: 9)),
                    if (data.vehicle.isNotEmpty)
                      pw.Text('Vehicle: ${data.vehicle}',
                          style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                        'Mechanic: ${data.mechanicName.isEmpty ? '—' : data.mechanicName}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                        'Assistant: ${data.assistantName.isEmpty ? '—' : data.assistantName}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Description', 'Amount'],
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1.4),
            },
            data: [
              [
                'Roadside assistance — ${data.issue}',
                _money.format(data.netAmount),
              ],
              [
                'GST (${data.taxPercent.toStringAsFixed(0)}%, included)',
                _money.format(data.taxAmount),
              ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Total paid: ${_money.format(data.amount)}',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Payment: ${data.paymentMethod.isEmpty ? '—' : data.paymentMethod}'
                  ' · Status: ${data.paymentStatus.isEmpty ? '—' : data.paymentStatus}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text('Settlement (internal)',
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Platform commission ${data.commissionPercent.toStringAsFixed(0)}%: '
            '${_money.format(data.commission)}   ·   '
            'Crew payout: ${_money.format(data.crewPayout)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'This invoice is generated from the stored job record. Figures '
            'show what was recorded on the job; they are not a tax filing '
            'document.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Write the PDF to a temporary file and open the system share sheet.
  /// Returns the file path that was shared, or null when sharing failed.
  static Future<String?> shareInvoice(InvoiceData data) async {
    final bytes = await buildPdf(data);
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/RoadResQ_${data.invoiceNumber}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
        subject: 'RoadResQ invoice ${data.invoiceNumber}',
        text: 'RoadResQ invoice for job ${data.requestId} '
            '(${_money.format(data.amount)}).',
      ),
    );
    return file.path;
  }
}
