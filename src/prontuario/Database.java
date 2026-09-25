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
import java.util.ArrayList;
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
