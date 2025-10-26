import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RatingWidget extends StatelessWidget {
  final double rating;
  final int totalReviews;
  final double size;
  final bool showCount;
  final Color? color;

  const RatingWidget({
    Key? key,
    required this.rating,
    this.totalReviews = 0,
    this.size = 16,
    this.showCount = true,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // النجوم
        ...List.generate(5, (index) {
          if (index < rating.floor()) {
            return Icon(
              Icons.star,
              size: size,
              color: color ?? Colors.amber,
            );
          } else if (index < rating) {
            return Icon(
              Icons.star_half,
              size: size,
              color: color ?? Colors.amber,
            );
          } else {
            return Icon(
              Icons.star_border,
              size: size,
              color: color ?? Colors.amber,
            );
          }
        }),
        if (showCount) ...[
          const SizedBox(width: 4),
          Text(
            '${rating.toStringAsFixed(1)}',
            style: GoogleFonts.cairo(
              fontSize: size * 0.8,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          if (totalReviews > 0) ...[
            const SizedBox(width: 4),
            Text(
              '($totalReviews)',
              style: GoogleFonts.cairo(
                fontSize: size * 0.7,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class RatingInputWidget extends StatefulWidget {
  final Function(double) onRatingChanged;
  final double initialRating;
  final double size;

  const RatingInputWidget({
    Key? key,
    required this.onRatingChanged,
    this.initialRating = 0,
    this.size = 40,
  }) : super(key: key);

  @override
  State<RatingInputWidget> createState() => _RatingInputWidgetState();
}

class _RatingInputWidgetState extends State<RatingInputWidget> {
  double _rating = 0;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _rating = index + 1.0;
            });
            widget.onRatingChanged(_rating);
          },
          child: Icon(
            index < _rating ? Icons.star : Icons.star_border,
            size: widget.size,
            color: Colors.amber,
          ),
        );
      }),
    );
  }
}