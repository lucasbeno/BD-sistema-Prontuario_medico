package prontuario;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import prontuario.dao.ConvenioDAO;
import prontuario.dao.DashboardDAO;
import prontuario.dao.MedicoDAO;
import prontuario.dao.PacienteDAO;
import prontuario.dao.RelatorioDAO;

public class App {
    private static final int PORTA = 8080;
    private static final Path PASTA_WEB = Path.of("web");

    private final PacienteDAO pacientes = new PacienteDAO();
    private final MedicoDAO medicos = new MedicoDAO();
    private final ConvenioDAO convenios = new ConvenioDAO();
    private final RelatorioDAO relatorios = new RelatorioDAO();
    private final DashboardDAO dashboard = new DashboardDAO();

    public static void main(String[] args) throws Exception {
        Database.carregarConfiguracao();
        try (var con = Database.getConnection()) {
            System.out.println("Conectado ao MySQL: " + con.getMetaData().getURL());
        }

        int porta = args.length > 0 ? Integer.parseInt(args[0]) : PORTA;
        HttpServer server = HttpServer.create(new InetSocketAddress(porta), 0);
        App app = new App();
        server.createContext("/api/", app::tratarApi);
        server.createContext("/", App::arquivoEstatico);
        server.start();
        System.out.println("Aplicação rodando em http://localhost:" + porta);
    }

    private void tratarApi(HttpExchange ex) throws IOException {
        try {
            String[] partes = ex.getRequestURI().getPath().replaceAll("/+$", "").split("/");
            String recurso = partes.length > 2 ? partes[2] : "";
            String id = partes.length > 3 ? URLDecoder.decode(partes[3], StandardCharsets.UTF_8) : null;
            String metodo = ex.getRequestMethod();

            Object resposta = switch (recurso) {
                case "dashboard" -> dashboard.carregar();
                case "relatorios" -> id == null ? relatorios.listar() : relatorios.executar(Integer.parseInt(id));
                case "pacientes" -> pacientes(metodo, id, lerFormulario(ex));
                case "medicos" -> medicos(metodo, id, lerFormulario(ex));
                case "convenios" -> convenios(metodo, id, lerFormulario(ex));
                default -> throw new NaoEncontrado("Recurso não encontrado: " + recurso);
            };
            enviarJson(ex, 200, resposta);
        } catch (NaoEncontrado e) {
            enviarJson(ex, 404, Map.of("erro", e.getMessage()));
        } catch (SQLException e) {
            enviarJson(ex, 400, Map.of("erro", mensagemAmigavel(e), "detalhe", e.getMessage()));
        } catch (IllegalArgumentException e) {
            enviarJson(ex, 400, Map.of("erro", e.getMessage()));
        } catch (Exception e) {
            e.printStackTrace();
            enviarJson(ex, 500, Map.of("erro", "Erro interno: " + e.getMessage()));
        }
    }

    private Object pacientes(String metodo, String cpf, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return pacientes.listar();
            case "POST":
                pacientes.inserir(obrigatorio(f, "cpf"), obrigatorio(f, "nome"), obrigatorio(f, "cep"),
                        opcional(f, "numero_apto"), inteiroOpcional(f, "codigo_convenio"), opcional(f, "telefone"));
                return Map.of("mensagem", "Paciente cadastrado");
            case "PUT":
                verificarAfetadas(pacientes.alterar(cpf, obrigatorio(f, "cpf"), obrigatorio(f, "nome"),
                        obrigatorio(f, "cep"), opcional(f, "numero_apto"), inteiroOpcional(f, "codigo_convenio")));
                return Map.of("mensagem", "Paciente alterado");
            case "DELETE":
                verificarAfetadas(pacientes.excluir(cpf));
                return Map.of("mensagem", "Paciente excluído");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object medicos(String metodo, String cpf, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return medicos.listar();
            case "POST":
                medicos.inserir(obrigatorio(f, "cpf"), obrigatorio(f, "nome"), obrigatorio(f, "cep"),
                        opcional(f, "numero_apto"), obrigatorio(f, "crm"), opcional(f, "especialidade"));
                return Map.of("mensagem", "Médico cadastrado");
            case "PUT":
                verificarAfetadas(medicos.alterar(cpf, obrigatorio(f, "cpf"), obrigatorio(f, "nome"),
                        obrigatorio(f, "cep"), opcional(f, "numero_apto"), obrigatorio(f, "crm"),
                        opcional(f, "especialidade")));
                return Map.of("mensagem", "Médico alterado");
            case "DELETE":
                verificarAfetadas(medicos.excluir(cpf));
                return Map.of("mensagem", "Médico excluído");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object convenios(String metodo, String codigo, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return convenios.listar();
            case "POST":
                convenios.inserir(obrigatorio(f, "nome"));
                return Map.of("mensagem", "Convênio cadastrado");
            case "PUT":
                verificarAfetadas(convenios.alterar(Integer.parseInt(codigo),
                        Integer.parseInt(obrigatorio(f, "codigo")), obrigatorio(f, "nome")));
                return Map.of("mensagem", "Convênio alterado");
            case "DELETE":
                verificarAfetadas(convenios.excluir(Integer.parseInt(codigo)));
                return Map.of("mensagem", "Convênio excluído (pacientes dele agora são particulares)");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private static String mensagemAmigavel(SQLException e) {
        return switch (e.getErrorCode()) {
            case 1062 -> "Registro duplicado: já existe um cadastro com esse valor único (CPF, CRM, nome...).";
            case 1451 -> "Não é possível excluir/alterar: existem registros que dependem deste (ex.: consultas).";
            case 1452 -> "Referência inválida: o registro relacionado não existe.";
            case 3819 -> "Valor inválido: violou a restrição " + restricao(e.getMessage()) + ".";
            case 1406 -> "Valor maior do que o tamanho permitido para o campo.";
            case 1644 -> e.getMessage();
            case 0 -> "Não foi possível conectar ao banco de dados: " + e.getMessage();
            default -> "Erro no banco de dados: " + e.getMessage();
        };
    }

    private static String restricao(String mensagem) {
        int i = mensagem.indexOf('\'');
        int j = mensagem.indexOf('\'', i + 1);
        return i >= 0 && j > i ? mensagem.substring(i + 1, j) : "CHECK";
    }

    private static void verificarAfetadas(int linhas) {
        if (linhas == 0) {
            throw new NaoEncontrado("Registro não encontrado");
        }
    }

    private static String obrigatorio(Map<String, String> f, String campo) {
        String valor = opcional(f, campo);
        if (valor == null) {
            throw new IllegalArgumentException("O campo '" + campo + "' é obrigatório");
        }
        return valor;
    }

    private static String opcional(Map<String, String> f, String campo) {
        String valor = f.get(campo);
        return valor == null || valor.isBlank() ? null : valor.trim();
    }

    private static Integer inteiroOpcional(Map<String, String> f, String campo) {
        String valor = opcional(f, campo);
        return valor == null ? null : Integer.valueOf(valor);
    }

    private static Map<String, String> lerFormulario(HttpExchange ex) throws IOException {
        String corpo = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        Map<String, String> campos = new HashMap<>();
        for (String par : corpo.split("&")) {
            if (par.isEmpty()) {
                continue;
            }
            String[] kv = par.split("=", 2);
            campos.put(URLDecoder.decode(kv[0], StandardCharsets.UTF_8),
                    kv.length > 1 ? URLDecoder.decode(kv[1], StandardCharsets.UTF_8) : "");
        }
        return campos;
    }

    private static void enviarJson(HttpExchange ex, int status, Object corpo) throws IOException {
        enviar(ex, status, "application/json; charset=utf-8", Json.escrever(corpo).getBytes(StandardCharsets.UTF_8));
    }

    private static void enviar(HttpExchange ex, int status, String tipo, byte[] bytes) throws IOException {
        ex.getResponseHeaders().set("Content-Type", tipo);
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = ex.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static void arquivoEstatico(HttpExchange ex) throws IOException {
        String caminho = ex.getRequestURI().getPath();
        if (caminho.equals("/")) {
            caminho = "/index.html";
        }
        Path arquivo = PASTA_WEB.resolve(caminho.substring(1)).normalize();
        if (!arquivo.startsWith(PASTA_WEB) || !Files.isRegularFile(arquivo)) {
            enviar(ex, 404, "text/plain; charset=utf-8", "Não encontrado".getBytes(StandardCharsets.UTF_8));
            return;
        }
        enviar(ex, 200, tipoConteudo(arquivo.toString()), Files.readAllBytes(arquivo));
    }

    private static String tipoConteudo(String nome) {
        for (var e : List.of(
                Map.entry(".html", "text/html; charset=utf-8"),
                Map.entry(".css", "text/css; charset=utf-8"),
                Map.entry(".js", "text/javascript; charset=utf-8"),
                Map.entry(".svg", "image/svg+xml"),
                Map.entry(".png", "image/png"))) {
            if (nome.endsWith(e.getKey())) {
                return e.getValue();
            }
        }
        return "application/octet-stream";
    }

    private static class NaoEncontrado extends RuntimeException {
        NaoEncontrado(String mensagem) {
            super(mensagem);
        }
    }
}
