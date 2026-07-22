package com.example.inventario_app;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(48, 48, 48, 48);
        root.setBackgroundColor(Color.WHITE);

        TextView title = new TextView(this);
        title.setText("Inventario");
        title.setTextColor(Color.BLACK);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 28);
        title.setGravity(Gravity.CENTER);

        TextView subtitle = new TextView(this);
        subtitle.setText("Version 1.0.1 de prueba para validar actualizaciones desde PDB Store.");
        subtitle.setTextColor(Color.DKGRAY);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, 24, 0, 0);

        root.addView(title);
        root.addView(subtitle);

        setContentView(root);
    }
}
