// lib/screens/auth/login_screen.dart
// 18/10/2025 21:51
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/home/home_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _stayConnected = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    setState(() {
      _stayConnected = settings.stayConnected;
    });

    if (settings.stayConnected) {
      _loginController.text = settings.savedLogin;
      _passwordController.text = await settings.getSavedPassword();
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

      final success = await authProvider.login(
        _loginController.text,
        _passwordController.text,
      );

      if (mounted && success) {
        await settingsProvider.saveCredentials(
          _loginController.text,
          _passwordController.text,
          _stayConnected,
        );

        // MODIFICATION : On ne charge QUE les infos de l'officine.
        await authProvider.loadOfficineInfo();

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connexion'),
            actions: [
              Row(
                children: [
                  const Text('Local', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: settings.isRemote,
                    onChanged: (value) {
                      if (value && settings.remoteIp.isEmpty) {
                        Constants.showSnackBar(
                          context,
                          'Veuillez renseigner une IP Distante dans la configuration.',
                          isError: true,
                        );
                        return;
                      }
                      settings.setConnectionMode(value);
                    },
                  ),
                  const Text('Distant', style: TextStyle(fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen()));
                    },
                    tooltip: 'Configuration',
                  ),
                ],
              ),
            ],
          ),
          body: child,
        );
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_open, size: 60, color: AppColors.primary),
                  const SizedBox(height: 20),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _loginController,
                    decoration: const InputDecoration(labelText: 'Login', prefixIcon: Icon(Icons.person)),
                    validator: (value) => value!.isEmpty ? 'Veuillez saisir votre login' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    validator: (value) => value!.isEmpty ? 'Veuillez saisir votre mot de passe' : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _stayConnected,
                          onChanged: (value) {
                            setState(() {
                              _stayConnected = value ?? false;
                            });
                          },
                        ),
                        const Text('Rester connecté'),
                      ],
                    ),
                  ),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.status == AuthStatus.Unauthenticated && auth.errorMessage != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: Text(
                            auth.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return auth.status == AuthStatus.Loading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                        child: const Text('Se connecter'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}