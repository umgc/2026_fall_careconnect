import 'package:flutter/material.dart';
import '../config/theme/app_theme.dart';

/// Popup widget that shows when receiving an incoming call
class IncomingCallPopup extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final bool isVideoCall;
  final String callerRole;
  final bool isConferenceInvite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallPopup({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.isVideoCall,
    required this.callerRole,
    this.isConferenceInvite = false,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallPopup> createState() => _IncomingCallPopupState();
}

class _IncomingCallPopupState extends State<IncomingCallPopup>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the call indicator
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Scale animation for the popup entrance
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 320,
                height: 480,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.backgroundSecondaryDarkTheme
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            widget.isConferenceInvite
                                ? 'Joining Existing Call'
                                : 'Incoming ${widget.isVideoCall ? 'Video' : 'Audio'} Call',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.isConferenceInvite
                                ? 'invited by ${widget.callerRole == 'CAREGIVER' ? 'Caregiver' : widget.callerRole.toLowerCase()}'
                                : 'from ${widget.callerRole == 'CAREGIVER' ? 'Caregiver' : widget.callerRole.toLowerCase()}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    // Caller Avatar and Name
                    Column(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: widget.isVideoCall
                                        ? [
                                            Colors.blue.shade400,
                                            Colors.blue.shade600,
                                          ]
                                        : [
                                            Colors.green.shade400,
                                            Colors.green.shade600,
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (widget.isVideoCall
                                              ? Colors.blue
                                              : Colors.green)
                                          .withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  widget.isVideoCall
                                      ? Icons.videocam
                                      : Icons.phone,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.callerName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.callerRole == 'PATIENT'
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.callerRole == 'PATIENT'
                                ? 'Patient'
                                : 'Caregiver',
                            style: TextStyle(
                              color: widget.callerRole == 'PATIENT'
                                  ? Colors.blue.shade700
                                  : Colors.purple.shade700,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Action Buttons
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Decline Button
                          GestureDetector(
                            onTap: widget.onDecline,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.red.shade500,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          ),

                          // Accept Button
                          GestureDetector(
                            onTap: widget.onAccept,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.green.shade500,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.isVideoCall
                                    ? Icons.videocam
                                    : Icons.phone,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Swipe hint
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swipe, size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to accept or decline',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
