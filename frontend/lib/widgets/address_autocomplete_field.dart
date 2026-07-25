import 'package:flutter/material.dart';
import '../services/google_places_service.dart';
import '../config/app_config.dart';

class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isRequired;
  final ValueChanged<ParsedAddress>? onAddressSelected;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType keyboardType;
  final String? googlePlacesApiKey;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = 'Start typing your address...',
    this.isRequired = false,
    this.onAddressSelected,
    this.onChanged,
    this.validator,
    this.keyboardType = TextInputType.streetAddress,
    this.googlePlacesApiKey,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  late FocusNode _focusNode;
  late GooglePlacesService _placesService;
  List<AddressSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _placesService = GooglePlacesService(
      apiKey: widget.googlePlacesApiKey,
      backendBase: AppConfig.getBackendBaseUrl(),
    );
    widget.controller.addListener(_updateSuggestions);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSuggestions);
    _focusNode.dispose();
    super.dispose();
  }

  void _updateSuggestions() async {
    final query = widget.controller.text.trim();
    
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    // Only fetch if query is at least 3 characters
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final suggestions = await _placesService.getSuggestions(query);
      
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = suggestions.isNotEmpty && _focusNode.hasFocus;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _showSuggestions = false;
        });
      }
    }

    widget.onChanged?.call(widget.controller.text);
  }

  void _selectSuggestion(AddressSuggestion suggestion) async {
    // Update the main input with full address
    widget.controller.text = suggestion.fullDescription;
    
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
      _loading = true;
    });

    try {
      // Parse the address into components
      final parsedAddress = await _placesService.getPlaceDetails(suggestion.placeId.isNotEmpty ? suggestion.placeId : suggestion.fullDescription);
      
      // Notify parent of parsed address
      if (mounted) {
        widget.onAddressSelected?.call(parsedAddress);
        setState(() {
          _loading = false;
        });
        _focusNode.unfocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing address: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(
            // Only show a floating label when one is provided; an empty label
            // means the field relies on its section header + hint text alone.
            labelText: widget.label.isEmpty ? null : widget.label,
            hintText: widget.hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            suffixIcon: _loading
                ? Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _suggestions.isNotEmpty
                    ? const Icon(Icons.arrow_drop_down)
                    : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
          validator: widget.validator,
          onTap: () {
            if (_suggestions.isNotEmpty) {
              setState(() {
                _showSuggestions = true;
              });
            }
          },
        ),
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              child: Material(
                color: Colors.white,
                elevation: 0,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      title: Text(
                        suggestion.mainText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        suggestion.secondaryText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      leading: Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: Colors.grey[700],
                      ),
                      onTap: () => _selectSuggestion(suggestion),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      tileColor: index.isEven ? Colors.grey[50] : Colors.white,
                      hoverColor: Colors.blue[50],
                    );
                  },
                ),
              ),
            ),
          ),
        if (widget.googlePlacesApiKey == null || widget.googlePlacesApiKey!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              '📍 Tip: Add a Google Places API key for real address suggestions',
              style: TextStyle(fontSize: 12, color: Colors.amber[700]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  'Google Places API active ✓',
                  style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
