package prontuario;

import java.util.Iterator;
import java.util.List;
import java.util.Map;

public final class Json {
    private Json() {
    }

    public static String escrever(Object valor) {
        StringBuilder sb = new StringBuilder();
        escrever(valor, sb);
        return sb.toString();
    }

    private static void escrever(Object valor, StringBuilder sb) {
        if (valor == null) {
            sb.append("null");
        } else if (valor instanceof Number || valor instanceof Boolean) {
            sb.append(valor);
        } else if (valor instanceof Map<?, ?> mapa) {
            sb.append('{');
            Iterator<? extends Map.Entry<?, ?>> it = mapa.entrySet().iterator();
            while (it.hasNext()) {
                Map.Entry<?, ?> e = it.next();
                texto(String.valueOf(e.getKey()), sb);
                sb.append(':');
                escrever(e.getValue(), sb);
                if (it.hasNext()) {
                    sb.append(',');
                }
            }
            sb.append('}');
        } else if (valor instanceof List<?> lista) {
            sb.append('[');
            for (int i = 0; i < lista.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                escrever(lista.get(i), sb);
            }
            sb.append(']');
        } else {
            texto(valor.toString(), sb);
        }
    }

    private static void texto(String s, StringBuilder sb) {
        sb.append('"');
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }
}
