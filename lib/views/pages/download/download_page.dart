import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/base/widget/get_binding_widget.dart';
import 'package:miru_app/views/pages/download/download_controller.dart';

class DownloadPage extends GetBindingWidget<DownloadController> {
  const DownloadPage({super.key});

  @override
  Bindings? binding() {
    return BindingsBuilder(() {
      Get.lazyPut(() => DownloadController());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("TODO"),
    );
  }
}