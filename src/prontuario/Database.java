package prontuario;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

public final class Database {
    private static String url;
    private static String user;
    private static String password;

    private Database() {
    }

    public static void carregarConfiguracao() throws IOException {
        Path arquivo = Path.of("db.properties");
        if (!Files.exists(arquivo)) {
            System.out.println("[aviso] db.properties não encontrado, usando db.properties.exemplo");
            arquivo = Path.of("db.properties.exemplo");
        }
        Properties props = new Properties();
        try (InputStream in = new FileInputStream(arquivo.toFile())) {
            props.load(in);
        }
        url = props.getProperty("db.url");
        user = props.getProperty("db.user");
        password = props.getProperty("db.password", "");
    }

    public static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(url, user, password);
    }

    public static Map<String, Object> paraTabela(PreparedStatement ps) throws SQLException {
        List<String> colunas = new ArrayList<>();
        List<List<Object>> linhas = new ArrayList<>();
        try (ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            for (int i = 1; i <= md.getColumnCount(); i++) {
                colunas.add(md.getColumnLabel(i));
            }
            while (rs.next()) {
                List<Object> linha = new ArrayList<>();
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    linha.add(rs.getObject(i));
                }
                linhas.add(linha);
            }
        }
        Map<String, Object> tabela = new LinkedHashMap<>();
        tabela.put("columns", colunas);
        tabela.put("rows", linhas);
        return tabela;
    }

    /** Liga os parâmetros (?) do comando, na ordem. null vira NULL no SQL. */
    public static void ligar(PreparedStatement ps, List<?> parametros) throws SQLException {
        for (int i = 0; i < parametros.size(); i++) {
            Object valor = parametros.get(i);
            if (valor == null) {
                ps.setNull(i + 1, Types.NULL);
            } else {
                ps.setObject(i + 1, valor);
            }
        }
    }

    /** SELECT com parâmetros -> lista de linhas (coluna -> valor). */
    public static List<Map<String, Object>> lista(Connection con, String sql, List<?> parametros) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ligar(ps, parametros);
            return paraLista(ps);
        }
    }

    public static List<Map<String, Object>> lista(String sql, Object... parametros) throws SQLException {
        try (Connection con = getConnection()) {
            return lista(con, sql, Arrays.asList(parametros));
        }
    }

    /** SELECT com parâmetros -> {columns: [...], rows: [[...], ...]}. */
    public static Map<String, Object> tabela(Connection con, String sql, List<?> parametros) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ligar(ps, parametros);
            return paraTabela(ps);
        }
    }

    /** INSERT / UPDATE / DELETE com parâmetros -> número de linhas afetadas. */
    public static int executar(String sql, Object... parametros) throws SQLException {
        try (Connection con = getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ligar(ps, Arrays.asList(parametros));
            return ps.executeUpdate();
        }
    }

    public static List<Map<String, Object>> paraLista(PreparedStatement ps) throws SQLException {
        List<Map<String, Object>> lista = new ArrayList<>();
        try (ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            while (rs.next()) {
                Map<String, Object> linha = new LinkedHashMap<>();
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    linha.put(md.getColumnLabel(i), rs.getObject(i));
                }
                lista.add(linha);
            }
        }
        return lista;
    }
}
