// lib/screens/auth/login_screen.dart
// 28/09/2025 00:29
import 'package:flutter/material.dart';
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
  final _loginController = TextEditingController(text: 'admin'); // Valeur pour test
  final _passwordController = TextEditingController(text: 'dcph1995'); // Valeur pour test
  bool _isPasswordVisible = false;

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        _loginController.text,
        _passwordController.text,
      );

      if (mounted && success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            tooltip: 'Configuration',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_open, size: 60, color: AppColors.primary),
                  const SizedBox(height: 20),
                  // Affichage du nom du pharmacien titulaire si disponible
                  if (authProvider.officine != null)
                    Text(
                      authProvider.officine!.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
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
                  const SizedBox(height: 15),
                  // Affiche le message d'erreur si la connexion échoue
                  if (authProvider.status == AuthStatus.Unauthenticated && authProvider.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15.0),
                      child: Text(
                        authProvider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                      ),
                    ),
                  authProvider.status == AuthStatus.Loading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                    child: const Text('Se connecter'),
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